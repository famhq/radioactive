_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
Group = require '../models/group'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
ProfanityService = require '../services/profanity'
EmbedService = require '../services/embed'
StreamService = require '../services/stream'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CHAT_MESSAGE.USER]

MAX_CONVERSATION_USER_IDS = 20

defaultConversationEmbed = [EmbedService.TYPES.CONVERSATION.USERS]

class ChatMessageCtrl
  create: ({body, conversationId, clientId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    Conversation.getById conversationId
    .then EmbedService.embed defaultConversationEmbed
    .tap ->
      new Promise (resolve) ->
        setTimeout resolve, 3000
    .then (conversation) ->
      console.log 'create'
      Conversation.hasPermission conversation, user.id
      .then (hasPermission) ->
        unless hasPermission
          router.throw status: 401, info: 'unauthorized'

        ChatMessage.create
          userId: user.id
          body: body
          clientId: clientId
          conversationId: conversationId
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
          cdnUrl = "https://#{config.CDN_HOST}/d/images/red_tritium"
          PushNotificationService.sendToConversation(
            conversation, {
              title: group?.name or User.getDisplayName(user)
              type: PushNotificationService.TYPES.PRIVATE_MESSAGE
              text: if group \
                    then "#{User.getDisplayName(user)}: #{body}"
                    else body
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

module.exports = new ChatMessageCtrl()
