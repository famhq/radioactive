_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
UserData = require '../models/user_data'
ChatMessage = require '../models/chat_message'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CHAT_MESSAGE.USER]

MAX_CONVERSATION_USER_IDS = 20

defaultUserEmbed = [EmbedService.TYPES.USER.DATA]

class ChatMessageCtrl
  create: ({body, toId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    msPlayed = Date.now() - user.joinTime?.getTime()

    if user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    EmbedService.embed defaultUserEmbed, user
    .then (user) ->
      toUser = if toId \
               then User.getById(toId).then EmbedService.embed defaultUserEmbed
               else Promise.resolve null
      toUser.then (toUser) ->
        if toUser and toUser.data.blockedUserIds.indexOf(user.id) isnt -1
          router.throw status: 400, info: 'block by user'

        ChatMessage.create
          userId: user.id
          body: body
          toId: toId
        .tap ->
          if toUser
            PushNotificationService.send(toUser, {
              title: 'New private message'
              type: PushNotificationService.TYPES.PRIVATE_MESSAGE
              text: "#{User.getDisplayName(user)} sent you a private message."
              url: "https://#{config.RED_TRITIUM_HOST}"
              data: {path: "/conversations/#{user.id}"}
            }).catch -> null

            meConversationUserIds = user.data.conversationUserIds

            meNewConversationUserIds = _.uniq [toUser.id].concat(
              _.filter meConversationUserIds, (id) -> id isnt toUser.id
            )
            if not _.isEqual meNewConversationUserIds, meConversationUserIds
              UserData.upsertByUserId user.id, {
                conversationUserIds: meNewConversationUserIds
              }
              key = "#{CacheService.PREFIXES.USER_DATA_CONVERSATION_USERS}:" +
                    "#{user.id}"
              CacheService.deleteByKey key

            toUserConversationIds = toUser.data.conversationUserIds
            toUserNewConversationIds = _.uniq [user.id].concat(
              _.filter toUserConversationIds, (id) -> id isnt user.id
            )
            toUserNewConversationIds = _.take(
              toUserNewConversationIds, MAX_CONVERSATION_USER_IDS
            )
            if not _.isEqual toUserNewConversationIds, meConversationUserIds
              UserData.upsertByUserId toUser.id, {
                conversationUserIds: toUserNewConversationIds
              }
              key = "#{CacheService.PREFIXES.USER_DATA_CONVERSATION_USERS}:" +
                    "#{toUser.id}"
              CacheService.deleteByKey key

          null

module.exports = new ChatMessageCtrl()
