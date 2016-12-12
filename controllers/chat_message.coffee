_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
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
  create: ({body, conversationId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, detail: 'unable to post...'

    Conversation.getById conversationId
    .then EmbedService.embed defaultConversationEmbed
    .then (conversation) ->
      Conversation.hasPermission conversation, user.id
      .then (hasPermission) ->
        unless hasPermission
          router.throw status: 401, detail: 'unauthorized'

        ChatMessage.create
          userId: user.id
          body: body
          conversationId: conversationId
        .tap ->
          userIds = conversation.userIds
          Conversation.updateById conversation.id, {
            lastUpdateTime: new Date()
            userData: _.zipObject userIds, _.map userIds, (userId) ->
              {isRead: userId isnt user.id}
          }
          PushNotificationService.sendToConversation(
            conversation, {
              title: if conversation.groupId \
                    then 'New group message'
                    else 'New private message'
              type: PushNotificationService.TYPES.PRIVATE_MESSAGE
              text: "#{User.getDisplayName(user)} sent a message."
              url: "https://#{config.SUPERNOVA_HOST}"
              data:
                path: if conversation.groupId \
                      then "/group/#{conversation.groupId}"
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
    .then (results) ->
      results.reverse()

module.exports = new ChatMessageCtrl()
