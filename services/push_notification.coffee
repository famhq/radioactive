_ = require 'lodash'
apn = require 'apn'
gcm = require 'node-gcm'
Promise = require 'bluebird'
uuid = require 'node-uuid'
webpush = require 'web-push'
ua = require 'universal-analytics'

config = require '../config'
EmbedService = require './embed'
User = require '../models/user'
Notification = require '../models/notification'
PushToken = require '../models/push_token'
Event = require '../models/event'
Group = require '../models/group'

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
  GROUP: 'group'
  STATUS: 'status'

defaultUserEmbed = [
  EmbedService.TYPES.USER.DATA
  EmbedService.TYPES.USER.GROUP_DATA
]
cdnUrl = "https://#{config.CDN_HOST}/d/images/starfire"

class PushNotificationService
  constructor: ->
    @apnConnection = new apn.Provider {
      cert: config.APN_CERT
      key: config.APN_KEY
      passphrase: config.APN_PASSPHRASE
      production: config.ENV is config.ENVS.PROD and not config.IS_STAGING
    }
    @isApnConnected = false
    @apnConnection.on 'connected', =>
      @isApnConnected = true
    @apnConnection.on 'error', (err) -> console.log err
    @apnConnection.on 'socketError', (err) -> console.log err
    @apnConnection.on 'transmissionError', -> null
    @apnConnection.on 'disconnect', =>
      @isApnConnected = false

    @gcmConnection = new gcm.Sender(config.GOOGLE_API_KEY)

    webpush.setVapidDetails(
      config.VAPID_SUBJECT,
      config.VAPID_PUBLIC_KEY,
      config.VAPID_PRIVATE_KEY
    )

  TYPES: TYPES

  isApnHealthy: =>
    Promise.resolve @isApnConnected

  isGcmHealthy: ->
    Promise.resolve true # TODO

  sendWeb: (token, message) ->
    webpush.sendNotification JSON.parse(token), JSON.stringify message

  sendIos: (token, {title, text, type, data}) =>
    data ?= {}

    notification = new apn.Notification {
      expiry: Math.floor(Date.now() / 1000) + ONE_DAY_SECONDS
      badge: 1
      sound: 'ping.aiff'
      alert: "#{title}: #{text}"
      topic: config.IOS_BUNDLE_ID
      category: type
      mutableContent: type is 'privateMessage'
      payload: {data, type, title, message: text}
      contentAvailable: 1
    }
    @apnConnection.send notification, token
    .then (response) ->
      if _.isEmpty response?.sent
        throw new Error 'message not sent'

  sendAndroid: (token, {title, text, type, data, icon}) =>
    new Promise (resolve, reject) =>
      notification = new gcm.Message {
        data:
          title: title
          message: text
          ledColor: [0, 255, 0, 0]
          image: if icon then icon else null
          data: data
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
          notId: uuid.v4()
      }

      @gcmConnection.send notification, [token], RETRY_COUNT, (err, result) ->
        successes = result?.success
        if err or not successes
          reject err
        else
          resolve true

  sendToConversation: (conversation, {skipMe, meUser, text} = {}) =>
    (if conversation.groupId
      Group.getById conversation.groupId
      .then (group) ->
        {group, userIds: group.userIds}
    else if conversation.eventId
      Event.getById conversation.eventId
      .then (event) ->
        {event, userIds: event.userIds}
    else
      Promise.resolve {userIds: conversation.userIds}
    ).then ({group, event, userIds}) =>
      if event
        return # FIXME FIXME: re-enable
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
          path: if group \
                then "/group/#{group.id}/chat/#{conversation.id}"
                else if event
                then "/event/#{event.id}"
                else "/conversation/#{conversation.id}"

      @sendToUserIds userIds, message, {
        skipMe, meUserId: meUser.id, groupId: conversation.groupId
      }

  sendToGroup: (group, message, {skipMe, meUserId, groupId} = {}) =>
    @sendToUserIds group.userIds, message, {skipMe, meUserId, groupId}

  sendToEvent: (event, message, {skipMe, meUserId, eventId} = {}) =>
    @sendToUserIds event.userIds, message, {skipMe, meUserId, eventId}

  sendToUserIds: (userIds, message, {skipMe, meUserId, groupId} = {}) ->
    Promise.each userIds, (userId) =>
      unless userId is meUserId
        user = User.getById userId
        if groupId
          user = user
                .then EmbedService.embed {embed: defaultUserEmbed, groupId}
        user
        .then (user) =>
          if user?.data and user.data.blockedUserIds.indexOf(meUserId) isnt -1
            return
          @send user, message

  send: (user, message) =>
    if config.ENV is config.ENVS.DEV and not message.forceDevSend
      console.log 'send notification', user.id, message

    unless message and (message.title or message.text)
      return Promise.reject new Error 'missing message'

    ga = ua config.GA_ID, user.id
    ga.event('push_notification', message.type, 'send').send()

    message.data ?= {}

    if [@TYPES.NEWS, @TYPES.NEW_PROMOTION].indexOf(message.type) is -1
      Notification.create {
        title: message.title
        text: message.text
        data: message.data
        type: message.type
        userId: user.id
      }

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
           else if sourceType is 'android'
           then @sendAndroid
           else @sendIos

      fn token, message
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


module.exports = new PushNotificationService()
