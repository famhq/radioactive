_ = require 'lodash'
router = require 'exoid-router'
cardBuilder = require 'card-builder'
uuid = require 'node-uuid'
Promise = require 'bluebird'
Joi = require 'joi'

User = require '../models/user'
UserItem = require '../models/user_item'
Ban = require '../models/ban'
Group = require '../models/group'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
GroupAuditLog = require '../models/group_audit_log'
GroupRole = require '../models/group_role'
GroupUser = require '../models/group_user'
EarnAction = require '../models/earn_action'
GroupUsersOnline = require '../models/group_users_online'
Language = require '../models/language'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
ProfanityService = require '../services/profanity'
EmbedService = require '../services/embed'
ImageService = require '../services/image'
StatsService = require '../services/stats'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.CHAT_MESSAGE.USER
  EmbedService.TYPES.CHAT_MESSAGE.MENTIONED_USERS
  EmbedService.TYPES.CHAT_MESSAGE.TIME
  EmbedService.TYPES.CHAT_MESSAGE.GROUP_USER
]

MAX_CONVERSATION_USER_IDS = 20
URL_REGEX = /\b(https?):\/\/[-A-Z0-9+&@#/%?=~_|!:,.;]*[A-Z0-9+&@#/%=~_|]/gi
CLASH_ROYALE_FRIEND_REGEX = ///
  https://link\.clashroyale\.com/invite/friend/([a-z]+)\?tag=([a-zA-Z0-9]+)([^ ]*)
///gi
CLASH_ROYALE_CLAN_REGEX = ///
  https://link\.clashroyale\.com/invite/clan/([a-z]+)\?tag=([a-zA-Z0-9]+)([^ ]*)
///gi
STICKER_REGEX = /(:[a-z_\^0-9]+:)/gi
IMAGE_REGEX = /\!\[(.*?)\]\((.*?)\)/gi
ADDON_REGEX = /\([^\)]+"addon:([a-zA-Z0-9-]+)\|([a-zA-Z0-9-]+)/i
CARD_BUILDER_TIMEOUT_MS = 1000
SMALL_IMAGE_SIZE = 200
MAX_LENGTH = 5000
ONE_DAY_SECONDS = 3600 * 24

RATE_LIMIT_CHAT_MESSAGES_TEXT = 6
RATE_LIMIT_CHAT_MESSAGES_TEXT_EXPIRE_S = 5

RATE_LIMIT_CHAT_MESSAGES_MEDIA = 2
RATE_LIMIT_CHAT_MESSAGES_MEDIA_EXPIRE_S = 10
# LARGE_IMAGE_SIZE = 1000

defaultConversationEmbed = [EmbedService.TYPES.CONVERSATION.USERS]
prepareFn = (item, {gameKeys} = {}) ->
  EmbedService.embed {
    embed: defaultEmbed
    gameKeys
  }, ChatMessage.default(item)
  .then (item) ->
    # TODO: rm?
    if item?.user?.flags?.isChatBanned isnt true
      item

class ChatMessageCtrl
  constructor: ->
    @cardBuilder = new cardBuilder {api: config.DEALER_API_URL}

  _checkRateLimit: (userId, isMedia, router) ->
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

  _checkIfBanned: (groupId, ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByGroupIdAndIp groupId, ipAddr, {preferCache: true}
      Ban.getByGroupIdAndUserId groupId, userId, {preferCache: true}
      Ban.isHoneypotBanned ipAddr, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId, isHoneypotBanned]) ->
      if bannedIp?.ip or bannedUserId?.userId or isHoneypotBanned
        router.throw
          status: 403
          info: "unable to post, banned #{userId}, #{ipAddr}"

  _checkSlowMode: (conversation, userId, router) ->
    isSlowMode = conversation?.data?.isSlowMode
    slowModeCooldownSeconds = conversation?.data?.slowModeCooldown
    if isSlowMode and slowModeCooldownSeconds
      ChatMessage.getLastTimeByUserIdAndConversationId userId, conversation.id
      .then (lastMeMessageTime) ->
        msSinceLastMessage = Date.now() - lastMeMessageTime
        cooldownSecondsLeft = slowModeCooldownSeconds -
                                Math.floor(msSinceLastMessage / 1000)
        if cooldownSecondsLeft > 0
          router.throw status: 403, info: 'unable to post, slow'
    else
      Promise.resolve null

  _checkStickers: (userId, stickers) ->
    if stickers
      UserItem.getAllByUserId userId
      .then (userItems) ->
        _.forEach stickers, (sticker) ->
          stickerText = sticker.replace /:/g, ''
          parts = stickerText.split '^'
          sticker = parts[0]
          level = parseInt(parts[1] or 1)
          ownedSticker = _.find userItems, {
            itemKey: sticker
          }
          ownedSticker?.itemLevel ?= 1
          hasSticker = ownedSticker and ownedSticker.itemLevel >= level
          unless hasSticker
            router.throw status: 401, info: 'sticker not found'

  _getMentions: (conversation, body) ->
    mentions = _.map _.uniq(body.match /\@[a-zA-Z0-9_-]+/g), (find) ->
      find.replace('@', '').toLowerCase()
    mentions = _.take mentions, 5 # so people don't abuse
    hasMentions = not _.isEmpty mentions

    (if hasMentions and conversation.groupId
      GroupRole.getAllByGroupId conversation.groupId, {preferCache: true}
    else
      Promise.resolve(null)
    )
    .then (roles) ->
      # TODO: match roles
      _.reduce mentions, (obj, mention) ->
        if _.find roles, {name: mention}
          obj.roleMentions.push mention
        else
          obj.userMentions.push mention
        obj
      , {roleMentions: [], userMentions: []}

  _sendPushNotifications: (options = {}) ->
    {conversation, chatMessage, user, body, userMentions,
      roleMentions, isImage} = options

    pushBody = if isImage then '[image]' else body

    Promise.all [
      (if conversation.groupId
        Group.getById conversation.groupId, {preferCache: true}
      else
        Promise.resolve null
      )

      Promise.map userMentions, (username) ->
        User.getByUsername username, {preferCache: true}
        .then (user) ->
          user?.id
    ]
    .then ([group, mentionUserIds]) ->
      mentionUserIds = _.filter mentionUserIds
      PushNotificationService.sendToConversation(
        conversation, {
          skipMe: true
          meUser: user
          text: pushBody
          mentionUserIds: mentionUserIds
          mentionRoles: roleMentions
          chatMessage: chatMessage
        }).catch -> null

  _createCards: (body, isImage, chatMessageId) =>
    urls = not isImage and body.match(URL_REGEX)

    (if _.isEmpty urls
      Promise.resolve null
    else if match = CLASH_ROYALE_FRIEND_REGEX.exec urls[0]
      language = match[1]
      tag = match[2]
      Promise.resolve {
        card:
          title: Language.get 'card.addFriendCardTitle', {
            language: language or 'en'
          }
          image: 'image'
          description: Language.get 'card.addFriendCardDescription', {
            language: language or 'en'
          }
          url: urls[0]
      }
    else if match = CLASH_ROYALE_CLAN_REGEX.exec urls[0]
      language = match[1]
      tag = match[2]
      Promise.resolve {
        card:
          title: Language.get 'card.joinClanCardTitle', {
            language: language or 'en'
          }
          image: 'image'
          description: Language.get 'card.joinClanCardDescription', {
            language: language or 'en'
          }
          url: urls[0]
      }
    else
      @cardBuilder.create {
        url: urls[0]
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/chatMessage/#{chatMessageId}/card"
      }
      .timeout CARD_BUILDER_TIMEOUT_MS
      .catch -> null
    )

  create: ({body, conversationId, clientId}, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    if user?.flags?.isModerator
      isProfane = false
    else
      isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post, profane'

    if body?.length > MAX_LENGTH
      router.throw status: 400, info: 'message is too long...'

    isImage = body.match IMAGE_REGEX
    stickers = body.match STICKER_REGEX
    isMedia = isImage or stickers
    isLink = body.match URL_REGEX
    isAddon = body.match ADDON_REGEX

    @_checkRateLimit user.id, isMedia, router
    .then ->
      Conversation.getById conversationId
      .catch (err) ->
        console.log 'err getting conversation', conversationId, body
        throw err
    .then EmbedService.embed {embed: defaultConversationEmbed}
    .then (conversation) =>
      (if conversation.groupId
        groupId = conversation.groupId

        GroupUsersOnline.upsert {userId: user.id, groupId}

        Promise.all [
          @_checkIfBanned groupId, ip, user.id, router
          @_checkSlowMode conversation, user.id, router
        ]
        .then ->
          permissions = [GroupUser.PERMISSIONS.SEND_MESSAGE]
          if isImage
            permissions = permissions.concat GroupUser.PERMISSIONS.SEND_IMAGE
          if isLink
            permissions = permissions.concat GroupUser.PERMISSIONS.SEND_LINK
          if isAddon
            permissions = permissions.concat GroupUser.PERMISSIONS.SEND_ADDON
          GroupUser.hasPermissionByGroupIdAndUser groupId, user, permissions, {
            channelId: conversationId
          }
          .then (hasPermission) ->
            unless hasPermission
              router.throw status: 400, info: 'no permission'
        .then ->
          if groupId
            Group.getById groupId, {preferCache: true}
          else
            Promise.resolve null


      else Promise.resolve null)
      .then (group) =>
        Conversation.hasPermission conversation, user.id
        .then (hasPermission) =>
          unless hasPermission
            router.throw status: 401, info: 'unauthorized'

          @_checkStickers user.id, stickers
        .then =>
          chatMessageId = uuid.v4()

          @_createCards body, isImage, chatMessageId
          .then ({card} = {}) ->
            body = body.replace CLASH_ROYALE_FRIEND_REGEX, ''
            body = body.replace CLASH_ROYALE_CLAN_REGEX, ''
            groupId = conversation.groupId or 'private'
            StatsService.sendEvent(
              user.id, 'chat_message', groupId, conversationId
            )
            ChatMessage.upsert {
              id: chatMessageId
              userId: user.id
              body: body
              clientId: clientId
              conversationId: conversationId
              groupId: conversation?.groupId
              card: card
            }, {
              prepareFn: (item) ->
                prepareFn item, {gameKeys: group?.gameKeys}
            }
      .tap ->
        if conversation.data?.isSlowMode
          ChatMessage.upsertSlowModeLog {
            userId: user.id, conversationId: conversation.id
          }
      .tap  ->
        (if conversation.groupId
          EarnAction.completeActionByGroupIdAndUserId(
            conversation.groupId
            user.id
            'chatMessage'
          )
          .catch -> null
        else
          Promise.resolve null
        )
        .then (rewards) ->
          {rewards}
      .then (chatMessage) =>
        userIds = conversation.userIds
        pickedConversation = _.pick conversation, [
          'userId', 'userIds', 'groupId', 'id'
        ]
        Conversation.upsert _.defaults(pickedConversation, {
          lastUpdateTime: new Date()
          isRead: false
        }), {userId: user.id}

        @_getMentions conversation, body
        .then ({userMentions, roleMentions}) =>
          @_sendPushNotifications {
            conversation, user, body, userMentions, roleMentions, isImage
            chatMessage
          }
        null # don't block

  deleteById: ({id}, {user}) ->
    ChatMessage.getById id
    .then (chatMessage) ->
      Conversation.getById chatMessage.conversationId
      .then (conversation) ->
        if conversation.groupId
          GroupUser.getByGroupIdAndUserId conversation.groupId, user.id
          .then EmbedService.embed {
            embed: [EmbedService.TYPES.GROUP_USER.ROLES]
          }
          .then (groupUser) ->
            hasPermission = GroupUser.hasPermission {
              meGroupUser: groupUser
              me: user
              permissions: [GroupUser.PERMISSIONS.DELETE_MESSAGE]
            }

            unless hasPermission
              router.throw
                status: 400, info: 'You don\'t have permission to do that'
          .then ->
            User.getById chatMessage.userId
            .then (otherUser) ->
              GroupAuditLog.upsert {
                groupId: conversation.groupId
                userId: user.id
                actionText: Language.get 'audit.deleteMessage', {
                  replacements:
                    name: User.getDisplayName otherUser
                  language: user.language
                }
              }
            ChatMessage.deleteByChatMessage chatMessage

  deleteAllByGroupIdAndUserId: ({groupId, userId, duration}, {user}) ->
    if groupId
      GroupUser.getByGroupIdAndUserId groupId, user.id
      .then EmbedService.embed {embed: [EmbedService.TYPES.GROUP_USER.ROLES]}
      .then (groupUser) ->
        permission = 'deleteMessage'
        hasPermission = GroupUser.hasPermission {
          meGroupUser: groupUser
          me: user
          permissions: [GroupUser.PERMISSIONS.DELETE_MESSAGE]
        }

        unless hasPermission
          router.throw
            status: 400, info: 'You don\'t have permission to do that'
      .then ->
        User.getById userId
        .then (otherUser) ->
          GroupAuditLog.upsert {
            groupId
            userId: user.id
            actionText: Language.get 'audit.deleteMessagesLast7d', {
              replacements:
                name: User.getDisplayName otherUser
              language: user.language
            }
          }
        ChatMessage.deleteAllByGroupIdAndUserId groupId, userId, {duration}

  updateCard: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.DEALER_SECRET
      ChatMessage.updateById params.id, {card: body.card}, {prepareFn}

  unsubscribeByConversationId: ({conversationId}, {user}, {socket}) ->
    ChatMessage.unsubscribeByConversationId conversationId, {socket}

  getLastTimeByMeAndConversationId: ({conversationId}, {user}, {socket}) ->
    ChatMessage.getLastTimeByUserIdAndConversationId user.id, conversationId

  getAllByConversationId: (options, {user}, socketInfo) =>
    {conversationId, minTimeUuid, maxTimeUuid, isStreamed} = options
    {emit, socket, route} = socketInfo

    Conversation.getById conversationId, {preferCache: true}
    .then (conversation) =>

      if conversation.groupId
        GroupUsersOnline.upsert {userId: user.id, groupId: conversation.groupId}

      Promise.all [
        if conversation.groupId
          Group.getById conversation.groupId, {preferCache: true}
        else
          Promise.resolve null

        (if conversation.groupId
          groupId = conversation.groupId
          permissions = [GroupUser.PERMISSIONS.READ_MESSAGE]
          GroupUser.hasPermissionByGroupIdAndUser groupId, user, permissions, {
            channelId: conversationId
          }
        else
          Conversation.hasPermission conversation, user.id)
      ]
      .then ([group, hasPermission]) =>
        unless hasPermission
          router.throw status: 401, info: 'unauthorized'

        limit = 25

        ChatMessage.getAllByConversationId conversationId, {
          limit: limit
          minTimeUuid: minTimeUuid
          maxTimeUuid: maxTimeUuid
          isStreamed: isStreamed
          emit: emit
          socket: socket
          route: route
          reverse: true
          initialPostFn: (item) ->
            prepareFn item, {gameKeys: group?.gameKeys}
        }


  uploadImage: ({}, {user, file}) ->
    router.assert {file}, {
      file: Joi.object().unknown().keys schemas.imageFile
    }
    ImageService.getSizeByBuffer (file.buffer)
    .then (size) ->
      key = "#{user.id}_#{uuid.v4()}"
      keyPrefix = "images/fam/cm/#{key}"

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
          key: "#{keyPrefix}.small.jpg"
          stream: ImageService.toStream
            buffer: file.buffer
            width: Math.min size.width, smallWidth
            height: Math.min size.height, smallHeight
            useMin: true

        ImageService.uploadImage
          key: "#{keyPrefix}.large.jpg"
          stream: ImageService.toStream
            buffer: file.buffer
            width: Math.min size.width, smallWidth * 5
            height: Math.min size.height, smallHeight * 5
            useMin: true
      ]
      .then (imageKeys) ->
        _.map imageKeys, (imageKey) ->
          "https://#{config.CDN_HOST}/#{imageKey}"
      .then ([smallUrl, largeUrl]) ->
        {smallUrl, largeUrl, key, width: size.width, height: size.height}

module.exports = new ChatMessageCtrl()
