_ = require 'lodash'
log = require 'loga'
apn = require 'apn'
gcm = require 'node-gcm'
Promise = require 'bluebird'
uuid = require 'node-uuid'

config = require '../config'
User = require '../models/user'
Notification = require '../models/notification'
PushToken = require '../models/push_token'

ONE_DAY_SECONDS = 3600 * 24
RETRY_COUNT = 10
CONSECUTIVE_ERRORS_UNTIL_INACTIVE = 10

TYPES =
  NEW_CARD: 'newCard'
  NEW_PROMOTION: 'sale'
  REWARD: 'reward'
  NEW_TRADE: 'newTrade'
  TRADE_UPDATE: 'tradeUpdate'
  PRIVATE_MESSAGE: 'privateMessage'
  NEW_FRIEND: 'newFriend'
  GIFT: 'gift'
  CREW: 'crew'
  STATUS: 'status'

class PushNotificationService
  constructor: ->
    @apnConnection = new apn.Provider {
      cert: config.APN_CERT
      key: config.APN_KEY
      passphrase: config.APN_PASSPHRASE
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

  TYPES: TYPES

  isApnHealthy: =>
    Promise.resolve @isApnConnected

  isGcmHealthy: ->
    Promise.resolve true # TODO

  sendIos: (token, {title, text, type, data}) =>
    data ?= {}

    device = new apn.Device token
    notification = new apn.Notification()
    notification.expiry = Math.floor(Date.now() / 1000) + ONE_DAY_SECONDS
    notification.badge = 1
    notification.sound = 'ping.aiff'
    notification.alert = "#{title}: #{text}"
    notification.payload = {data, type, title, message: text}
    notification.contentAvailable = true
    @apnConnection.pushNotification notification, device
    Promise.resolve true

  sendAndroid: (token, {title, text, type, data}) =>
    new Promise (resolve, reject) =>
      notification = new gcm.Message {
        data:
          title: title
          message: text
          data: data
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

  send: (user, message) =>
    unless message and (message.title or message.text)
      return Promise.reject new Error 'missing message'

    message.data ?= {}

    if [@TYPES.NEW_CARD, @TYPES.NEW_PROMOTION].indexOf(message.type) is -1
      Notification.create {
        title: message.title
        text: message.text
        data: message.data
        type: message.type
        userId: user.id
      }

    if user.flags.blockedNotifications?[message.type] is true
      return Promise.resolve null

    successfullyPushedToNative = false

    PushToken.getAllByUserId user.id
    .map ({id, sourceType, token, errorCount}) =>
      if sourceType is 'android'
        @sendAndroid token, message
        .then ->
          # console.log 'android push success'
          successfullyPushedToNative = true
          if errorCount
            PushToken.updateById id, {
              errorCount: 0
            }
        .catch (err) ->
          console.log 'android push error'
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
          # log.trace err
      else if sourceType is 'ios'
        @sendIos token, message
        .then ->
          # console.log 'ios push success'
          successfullyPushedToNative = true
          if errorCount
            PushToken.updateById id, {
              errorCount: 0
            }
        .catch (err) ->
          console.log 'ios push error'
          newErrorCount = errorCount + 1
          PushToken.updateById id, {
            errorCount: newErrorCount
            isActive: newErrorCount < CONSECUTIVE_ERRORS_UNTIL_INACTIVE
          }
          # log.trace err
          if newErrorCount >= CONSECUTIVE_ERRORS_UNTIL_INACTIVE
            PushToken.getAllByUserId user.id
            .then (tokens) ->
              if _.isEmpty tokens
                User.updateById user.id, {
                  hasPushToken: false
                }


module.exports = new PushNotificationService()
