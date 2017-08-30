_ = require 'lodash'
router = require 'exoid-router'
cardBuilder = require 'card-builder'
uuid = require 'node-uuid'
Promise = require 'bluebird'
Joi = require 'joi'

User = require '../models/user'
Ban = require '../models/ban'
Group = require '../models/group'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
ProfanityService = require '../services/profanity'
EmbedService = require '../services/embed'
StreamService = require '../services/stream'
ImageService = require '../services/image'
StatsService = require '../services/stats'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CHAT_MESSAGE.USER]

MAX_CONVERSATION_USER_IDS = 20
URL_REGEX = /\b(https?):\/\/[-A-Z0-9+&@#/%?=~_|!:,.;]*[A-Z0-9+&@#/%=~_|]/gi
STICKER_REGEX = /(:[a-z_]+:)/gi
IMAGE_REGEX = /\!\[(.*?)\]\((.*?)\)/gi
CARD_BUILDER_TIMEOUT_MS = 1000
SMALL_IMAGE_SIZE = 200
MAX_LENGTH = 5000

RATE_LIMIT_CHAT_MESSAGES_TEXT = 6
RATE_LIMIT_CHAT_MESSAGES_TEXT_EXPIRE_S = 5

RATE_LIMIT_CHAT_MESSAGES_MEDIA = 2
RATE_LIMIT_CHAT_MESSAGES_MEDIA_EXPIRE_S = 10
# LARGE_IMAGE_SIZE = 1000

defaultConversationEmbed = [EmbedService.TYPES.CONVERSATION.USERS]

class ChatMessageCtrl
  constructor: ->
    @cardBuilder = new cardBuilder {api: config.DEALER_API_URL}

  checkRateLimit: (userId, isMedia, router) ->
    if isMedia
      key = "#{CacheService.PREFIXES.RATE_LIMIT_CHAT_MESSAGES_MEDIA}:#{userId}"
      rateLimit = RATE_LIMIT_CHAT_MESSAGES_MEDIA
      rateLimitExpireS = RATE_LIMIT_CHAT_MESSAGES_MEDIA_EXPIRE_S
    else
      key = "#{CacheService.PREFIXES.RATE_LIMIT_CHAT_MESSAGES_TEXT}:#{userId}"
      rateLimit = RATE_LIMIT_CHAT_MESSAGES_TEXT
      rateLimitExpireS = RATE_LIMIT_CHAT_MESSAGES_TEXT_EXPIRE_S

    CacheService.get key
    .then (amount) ->
      amount ?= 0
      if amount >= rateLimit
        router.throw status: 429, info: 'too many requests'
      CacheService.set key, amount + 1, {
        expireSeconds: rateLimitExpireS
      }

  checkIfBanned: (ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByIp ipAddr, {preferCache: true}
      Ban.getByUserId userId, {preferCache: true}
      Ban.isHoneypotBanned ipAddr, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId, isHoneypotBanned]) ->
      if bannedIp?.ip or bannedUserId?.userId or isHoneypotBanned
        router.throw status: 403, 'unable to post'

  create: ({body, conversationId, clientId}, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    if body?.length > MAX_LENGTH
      router.throw status: 400, info: 'message is too long...'

    isImage = body.match(IMAGE_REGEX)
    isSticker = body.match(STICKER_REGEX)
    isMedia = isImage or isSticker

    @checkIfBanned ip, user.id, router
    .then =>
      @checkRateLimit user.id, isMedia, router
    .then ->
      Conversation.getById conversationId
    .then EmbedService.embed {embed: defaultConversationEmbed}
    .then (conversation) =>
      Conversation.hasPermission conversation, user.id
      .then (hasPermission) =>
        unless hasPermission
          router.throw status: 401, info: 'unauthorized'

        chatMessageId = uuid.v4()

        urls = not isImage and body.match(URL_REGEX)

        (if _.isEmpty urls
          Promise.resolve null
        else
          @cardBuilder.create {
            url: urls[0]
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/chatMessage/#{chatMessageId}/card"
          }
          .timeout CARD_BUILDER_TIMEOUT_MS
          .catch -> null
        )
        .then ({card} = {}) ->
          groupId = conversation.groupId or 'private'
          StatsService.sendEvent(
            user.id, 'chat_message', groupId, conversationId
          )
          ChatMessage.create
            id: chatMessageId
            userId: user.id
            body: body
            clientId: clientId
            conversationId: conversationId
            groupId: conversation?.groupId
            card: card
        .then ->
          userIds = conversation.userIds
          Conversation.updateById conversation.id, {
            lastUpdateTime: new Date()
            # TODO: different way to track if read (groups get too large)
            # should store lastReadTime on user for each group
            userData: unless conversation.groupId
              _.zipObject userIds, _.map userIds, (userId) ->
                {isRead: userId is user.id}
          }
          pushBody = if isImage then '[image]' else body

          (if conversation.groupId
            Group.getById conversation.groupId, {preferCache: true}
          else
            Promise.resolve null
          )
          .then (group) ->
            unless group?.type is 'public'
              PushNotificationService.sendToConversation(
                conversation, {
                  skipMe: true
                  meUser: user
                  text: pushBody
                }).catch -> null

  deleteById: ({id}, {user}) ->
    unless user.flags.isModerator
      router.throw status: 400, info: 'no permission'
    ChatMessage.deleteById id

  updateCard: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.DEALER_SECRET
      ChatMessage.updateById params.id, {card: body.card}

  getAllByConversationId: ({conversationId}, {user}, {emit, socket, route}) ->
    start = Date.now()
    Conversation.getById conversationId, {preferCache: true}
    .then (conversation) ->
      start = Date.now()
      Conversation.hasPermission conversation, user.id
      .then (hasPermission) ->
        start = Date.now()
        unless hasPermission
          router.throw status: 401, info: 'unauthorized'

        limit = 40

        StreamService.stream {
          emit
          socket
          route
          limit: limit
          promise: ChatMessage.getAllByConversationId conversationId, {
            limit, isStreamed: true
          }
          postFn: (item) ->
            EmbedService.embed {embed: defaultEmbed}, ChatMessage.default(item)
            .then (item) ->
              if item?.user?.flags?.isChatBanned isnt true
                item
        }
        .tap ->
          start = Date.now()

  uploadImage: ({}, {user, file}) ->
    router.assert {file}, {
      file: Joi.object().unknown().keys schemas.imageFile
    }
    ImageService.getSizeByBuffer (file.buffer)
    .then (size) ->
      key = "#{user.id}_#{uuid.v4()}"
      keyPrefix = "images/starfire/cm/#{key}"

      aspectRatio = size.width / size.height
      # 10 is to prevent super wide/tall images from being uploaded
      if (aspectRatio < 1 and aspectRatio < 10) or aspectRatio < 0.1
        smallWidth = SMALL_IMAGE_SIZE
        smallHeight = smallWidth / aspectRatio
      else
        smallHeight = SMALL_IMAGE_SIZE
        smallWidth = smallHeight * aspectRatio

      Promise.all [
        ImageService.uploadImage
          key: "#{keyPrefix}.small.png"
          stream: ImageService.toStream
            buffer: file.buffer
            width: smallWidth
            height: smallHeight
            useMin: true

        ImageService.uploadImage
          key: "#{keyPrefix}.large.png"
          stream: ImageService.toStream
            buffer: file.buffer
            width: smallWidth * 5
            height: smallHeight * 5
            useMin: true
      ]
      .then (imageKeys) ->
        _.map imageKeys, (imageKey) ->
          "https://#{config.CDN_HOST}/#{imageKey}"
      .then ([smallUrl, largeUrl]) ->
        {smallUrl, largeUrl, key, width: size.width, height: size.height}

module.exports = new ChatMessageCtrl()
