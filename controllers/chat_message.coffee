_ = require 'lodash'
router = require 'exoid-router'
cardBuilder = require 'card-builder'
uuid = require 'node-uuid'
Promise = require 'bluebird'
Joi = require 'joi'

User = require '../models/user'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
Group = require '../models/group'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
ProfanityService = require '../services/profanity'
EmbedService = require '../services/embed'
StreamService = require '../services/stream'
ImageService = require '../services/image'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CHAT_MESSAGE.USER]

MAX_CONVERSATION_USER_IDS = 20
URL_REGEX = /\b(https?):\/\/[-A-Z0-9+&@#/%?=~_|!:,.;]*[A-Z0-9+&@#/%=~_|]/gi
IMAGE_REGEX = /\(\!\[(.*?)\]\local:\/\/(.*?)_([0-9.]+)\)/gi
CARD_BUILDER_TIMEOUT_MS = 1000
SMALL_IMAGE_WIDTH = 100
LARGE_IMAGE_WIDTH = 1000

defaultConversationEmbed = [EmbedService.TYPES.CONVERSATION.USERS]

class ChatMessageCtrl
  constructor: ->
    @cardBuilder = new cardBuilder {api: config.DEALER_API_URL}

  create: ({body, conversationId, clientId}, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    Conversation.getById conversationId
    .then EmbedService.embed defaultConversationEmbed
    .then (conversation) =>
      Conversation.hasPermission conversation, user.id
      .then (hasPermission) =>
        unless hasPermission
          router.throw status: 401, info: 'unauthorized'

        chatMessageId = uuid.v4()

        urls = body.match URL_REGEX

        (if _.isEmpty urls
          Promise.resolve null
        else
          @cardBuilder.create {
            url: urls[0]
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/chatMessage/#{chatMessageId}/card"
          }
          .timeout CARD_BUILDER_TIMEOUT_MS
        )
        .then ({card} = {}) ->
          ChatMessage.create
            id: chatMessageId
            userId: user.id
            body: body
            clientId: clientId
            conversationId: conversationId
            card: card
        .then ->
          if conversation.groupId
            Group.getById conversation.groupId
          else
            Promise.resolve null
        .tap (group) ->
          userIds = conversation.userIds
          Conversation.updateById conversation.id, {
            lastUpdateTime: new Date()
            userData: _.zipObject userIds, _.map userIds, (userId) ->
              {isRead: userId is user.id}
          }
          pushBody = if body.match(IMAGE_REGEX) then '[image]' else body
          cdnUrl = "https://#{config.CDN_HOST}/d/images/red_tritium"
          PushNotificationService.sendToConversation(
            conversation, {
              title: group?.name or User.getDisplayName(user)
              type: PushNotificationService.TYPES.PRIVATE_MESSAGE
              text: if group \
                    then "#{User.getDisplayName(user)}: #{pushBody}"
                    else pushBody
              url: "https://#{config.SUPERNOVA_HOST}"
              icon: if group \
                    then "#{cdnUrl}/groups/badges/#{group.badgeId}.png"
                    else user?.avatarImage?.versions[0].url
              data:
                conversationId: conversation.id
                contextId: conversation.id
                path: if group \
                      then "/group/#{group.id}"
                      else "/conversation/#{conversationId}"
          }, {skipMe: true, meUserId: user.id}).catch -> null

  updateCard: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.DEALER_SECRET
      ChatMessage.updateById params.id, {card: body.card}

  getAllByConversationId: ({conversationId}, {user}, {emit, socket, route}) ->
    StreamService.stream {
      emit
      socket
      route
      limit: 30
      promise: ChatMessage.getAllByConversationId conversationId, {
        isStreamed: true
      }
      postFn: (item) ->
        EmbedService.embed defaultEmbed, ChatMessage.default(item)
        .then (item) ->
          if item.user?.flags?.isChatBanned isnt true
            item
    }

  uploadImage: ({}, {user, file}) ->
    router.assert {file}, {
      file: Joi.object().unknown().keys schemas.imageFile
    }
    ImageService.getSizeByBuffer (file.buffer)
    .then (size) ->
      ratio = Math.round(100 * size.width / size.height) / 100
      key = "#{user.id}_#{uuid.v4()}_#{ratio}"
      keyPrefix = "images/red_tritium/cm/#{key}"

      Promise.all [
        ImageService.uploadImage
          key: "#{keyPrefix}.small.png"
          stream: ImageService.toStream
            buffer: file.buffer
            width: SMALL_IMAGE_WIDTH

        ImageService.uploadImage
          key: "#{keyPrefix}.large.png"
          stream: ImageService.toStream
            buffer: file.buffer
            width: LARGE_IMAGE_WIDTH
      ]
      .then (imageKeys) ->
        _.map imageKeys, (imageKey) ->
          "https://#{config.CDN_HOST}/#{imageKey}"
      .then ([smallUrl, largeUrl]) ->
        {smallUrl, largeUrl, key}

module.exports = new ChatMessageCtrl()
