_ = require 'lodash'
apn = require 'apn'
gcm = require 'node-gcm'
Promise = require 'bluebird'
uuid = require 'node-uuid'
webpush = require 'web-push'
request = require 'request-promise'
randomSeed = require 'random-seed'

config = require '../config'
EmbedService = require './embed'
User = require '../models/user'
Notification = require '../models/notification'
PushToken = require '../models/push_token'
Event = require '../models/event'
Group = require '../models/group'
GroupUser = require '../models/group_user'
Language = require '../models/language'
StatsService = require './stats'

ONE_DAY_SECONDS = 3600 * 24
RETRY_COUNT = 10
CONSECUTIVE_ERRORS_UNTIL_INACTIVE = 10

TYPES =
  NEW_PROMOTION: 'sale'
  NEWS: 'news'
  DAILY_RECAP: 'dailyRecap'
  EVENT: 'event'
  CHAT_MESSAGE: 'chatMessage'
  PRIVATE_MESSAGE: 'privateMessage'
  NEW_FRIEND: 'newFriend'
  PRODUCT: 'product'
  GROUP: 'group'
  STATUS: 'status'
  VIDEO: 'video'

defaultUserEmbed = [
  EmbedService.TYPES.USER.DATA
  EmbedService.TYPES.USER.GROUP_DATA
]
cdnUrl = "https://#{config.CDN_HOST}/d/images/starfire"

class PushNotificationService
  constructor: ->
    @gcmConn = new gcm.Sender(config.GOOGLE_API_KEY)

    webpush.setVapidDetails(
      config.VAPID_SUBJECT,
      config.VAPID_PUBLIC_KEY,
      config.VAPID_PRIVATE_KEY
    )

  TYPES: TYPES

  isGcmHealthy: ->
    Promise.resolve true # TODO

  sendWeb: (token, message) ->
    # doesn't seem to work with old VAPID tokens
    # tokenObj = JSON.parse token
    # request 'https://iid.googleapis.com/v1/web/iid', {
    #   json: true
    #   method: 'POST'
    #   headers:
    #     'Authorization': "key=#{config.GOOGLE_API_KEY}"
    #   body:
    #     endpoint: tokenObj.endpoint
    #     keys: tokenObj.keys
    # }
    webpush.sendNotification JSON.parse(token), JSON.stringify message

  sendIos: (token, {title, text, type, data, icon}) ->
    request 'https://iid.googleapis.com/iid/v1:batchImport', {
      json: true
      method: 'POST'
      headers:
        'Authorization': "key=#{config.GOOGLE_API_KEY}"
      body:
        apns_tokens: [token]
        sandbox: false
        application: 'com.clay.redtritium'
    }
    .then (response) ->
      newToken = response?.results?[0]?.registration_token
      if newToken
        PushToken.updateByToken token, {
          sourceType: 'ios-fcm'
          apnsToken: token
          token: newToken
        }
    .then =>
      @sendFcm token, {title, text, type, data, icon}, {isiOS: true}

  sendFcm: (to, {title, text, type, data, icon, toType, notId}, {isiOS} = {}) =>
    toType ?= 'token'
    new Promise (resolve, reject) =>
      messageOptions = {
        priority: 'high'
        contentAvailable: true
      }
      # ios and android take different formats for whatever reason...
      # if you pass notification to android, it uses that and doesn't use data
      # https://github.com/phonegap/phonegap-plugin-push/issues/387
      if isiOS
        messageOptions.notification =
          title: title
          body: text
          # icon: 'notification_icon'
          color: config.NOTIFICATION_COLOR
        messageOptions.data = data
      else
        messageOptions.data =
          title: title
          message: text
          ledColor: [0, 255, 0, 0]
          image: if icon then icon else null
          payload: data
          data: data
          # https://github.com/phonegap/phonegap-plugin-push/issues/158
          # unfortunately causes flash as app opens and closes.
          # spent 3 hours trying to solve and no luck
          # https://github.com/phonegap/phonegap-plugin-push/issues/1846
          # 'force-start': 1
          # 'content-available': true
          priority: 1
          actions: _.filter [
            if type in [
              @TYPES.CHAT_MESSAGE
              @TYPES.PRIVATE_MESSAGE
            ]
              {
                title: 'REPLY'
                callback: 'app.pushActions.reply'
                foreground: false
                inline: true
              }
          ]
          type: type
          icon: 'notification_icon'
          color: config.NOTIFICATION_COLOR
          notId: notId or (Date.now() % 100000) # should be int, not uuid.v4()
          # android_channel_id: 'test'

      notification = new gcm.Message messageOptions

      if toType is 'token'
        toObj = {registrationTokens: [to]}
      else if toType is 'topic' and to
        toObj = {topic: "/topics/#{to}"}
        # toObj = {condition: "'#{to}' in topics || '#{to}2' in topics"}

      @gcmConn.send notification, toObj, RETRY_COUNT, (err, result) ->
        successes = result?.success or result?.message_id
        if err or not successes
          reject err
        else
          resolve true

  sendToConversation: (conversation, {skipMe, meUser, text} = {}) =>
    (if conversation.groupId
      Group.getById conversation.groupId
      .then (group) ->
        if group.type is 'public'
          {group, userIds: []}
        else
          GroupUser.getAllByGroupId conversation.groupId
          .map (groupUser) -> groupUser.userId
          .then (userIds) ->
            {group, userIds}
    else if conversation.eventId
      Event.getById conversation.eventId
      .then (event) ->
        {event, userIds: event.userIds}
    else
      Promise.resolve {userIds: conversation.userIds}
    ).then ({group, event, userIds}) =>
      if event
        return # FIXME FIXME: re-enable

      if group
        path = {
          key: 'groupChatConversation'
          params:
            id: group.id
            conversationId: conversation.id
            gameKey: config.DEFAULT_GAME_KEY
        }
      else if event
        path = {
          key: 'event'
          params:
            id: event.id
            gameKey: config.DEFAULT_GAME_KEY
        }
      else
        path = {
          key: 'conversation'
          params:
            id: conversation.id
            gameKey: config.DEFAULT_GAME_KEY
        }

      message =
        title: event?.name or group?.name or User.getDisplayName meUser
        type: if group or event \
              then @TYPES.CHAT_MESSAGE
              else @TYPES.PRIVATE_MESSAGE
        text: if group or event \
              then "#{User.getDisplayName(meUser)}: #{text}"
              else text
        url: "https://#{config.STARFIRE_HOST}"
        icon: if group \
              then "#{cdnUrl}/groups/badges/#{group.badgeId}.png"
              else meUser?.avatarImage?.versions[0].url
        data:
          conversationId: conversation.id
          contextId: conversation.id
          path: path
        notId: randomSeed.create(conversation.id)(Number.MAX_SAFE_INTEGER)

      @sendToUserIds userIds, message, {
        skipMe, meUserId: meUser.id, groupId: conversation.groupId
      }

  sendToGroup: (group, message, {skipMe, meUserId, groupId} = {}) =>
    @sendToUserIds group.userIds, message, {skipMe, meUserId, groupId}

  sendToGroupTopic: (group, message) =>
    topic = "group-#{group.id}"
    language = group.language
    if message.titleObj
      message.title = Language.get message.titleObj.key, {
        file: 'pushNotifications'
        language: language
        replacements: message.titleObj.replacements
      }
    if message.textObj
      message.text = Language.get message.textObj.key, {
        file: 'pushNotifications'
        language: language
        replacements: message.textObj.replacements
      }

    message = {
      toType: 'topic'
      type: TYPES.VIDEO
      title: message.title
      text: message.text
      data: message.data
    }

    if config.ENV isnt config.ENVS.PROD or config.IS_STAGING
      console.log 'send notification', group.id, JSON.stringify message
      return

    @sendFcm topic, message

  sendToEvent: (event, message, {skipMe, meUserId, eventId} = {}) =>
    @sendToUserIds event.userIds, message, {skipMe, meUserId, eventId}

  sendToUserIds: (userIds, message, {skipMe, meUserId, groupId} = {}) ->
    Promise.each userIds, (userId) =>
      unless userId is meUserId
        user = User.getById userId, {preferCache: true}
        if groupId
          user = user.then EmbedService.embed {embed: defaultUserEmbed, groupId}
        user
        .then (user) =>
          if not user or (
            user.data and user.data.blockedUserIds.indexOf(meUserId) isnt -1
          )
            return
          @send user, message

  send: (user, message) =>
    unless message and (
      message.title or message.text or message.titleObj or message.textObj
    )
      return Promise.reject new Error 'missing message'

    StatsService.sendEvent user.id, 'push_notification', message.type, 'send'

    language = user.language or Language.getLanguageByCountry user.country

    message.data ?= {}
    if message.titleObj
      message.title = Language.get message.titleObj.key, {
        file: 'pushNotifications'
        language: language
        replacements: message.titleObj.replacements
      }
    if message.textObj
      message.text = Language.get message.textObj.key, {
        file: 'pushNotifications'
        language: language
        replacements: message.textObj.replacements
      }

    if config.ENV is config.ENVS.DEV and not message.forceDevSend
      console.log 'send notification', user.id, message
      # return

    # if [@TYPES.NEWS, @TYPES.NEW_PROMOTION].indexOf(message.type) is -1
    #   Notification.create {
    #     title: message.title
    #     text: message.text
    #     data: message.data
    #     type: message.type
    #     userId: user.id
    #   }

    if user.flags.blockedNotifications?[message.type] is true
      return Promise.resolve null

    if user.groupData and
        user.groupData.globalBlockedNotifications?[message.type] is true
      return Promise.resolve null

    successfullyPushedToNative = false


    PushToken.getAllByUserId user.id
    .map ({id, sourceType, token, errorCount}) =>
      fn = if sourceType is 'web' \
           then @sendWeb
           else if sourceType in ['android', 'ios-fcm', 'web-fcm']
           then @sendFcm
           else @sendIos

      fn token, message, {isiOS: sourceType is 'ios-fcm'}
      .then ->
        successfullyPushedToNative = true
        if errorCount
          PushToken.updateById id, {
            errorCount: 0
          }
      .catch (err) ->
        newErrorCount = errorCount + 1
        PushToken.updateById id, {
          errorCount: newErrorCount
          isActive: newErrorCount < CONSECUTIVE_ERRORS_UNTIL_INACTIVE
        }
        if newErrorCount >= CONSECUTIVE_ERRORS_UNTIL_INACTIVE
          PushToken.getAllByUserId user.id
          .then (tokens) ->
            if _.isEmpty tokens
              User.updateById user.id, {
                hasPushToken: false
              }

  subscribeToTopicByUserId: (userId, topic) ->
    console.log 'subscribeTopic', topic
    PushToken.getAllByUserId userId
    .map ({sourceType, token}) ->
      unless sourceType in ['android', 'ios-fcm', 'web-fcm']
        return
      base = 'https://iid.googleapis.com/iid/v1'
      request "#{base}/#{token}/rel/topics/#{topic}", {
        json: true
        method: 'POST'
        headers:
          'Authorization': "key=#{config.GOOGLE_API_KEY}"
        body: {}
      }
      .catch (err) ->
        console.log 'sub topic err'

  subscribeToAllTopicsByUser: (user, {language} = {}) =>
    Promise.all [
      @subscribeToTopicByUserId user.id, 'all'
      @subscribeToTopicByUserId user.id, (language or user.language)

      GroupUser.getAllByUserId user.id
      .map ({groupId}) =>
        @subscribeToTopicByUserId user.id, "group-#{groupId}"
    ]


module.exports = new PushNotificationService()
