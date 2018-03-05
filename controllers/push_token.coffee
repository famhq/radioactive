_ = require 'lodash'
Joi = require 'joi'
Promise = require 'bluebird'
router = require 'exoid-router'
request = require 'request-promise'

PushToken = require '../models/push_token'
User = require '../models/user'
PushNotificationService = require '../services/push_notification'
schemas = require '../schemas'
config = require '../config'

class PushTokensCtrl
  create: ({token, sourceType, language, deviceId}, {user, appKey}) ->
    userId = user.id
    valid = Joi.validate {userId, token, sourceType},
      userId: schemas.user.id.optional()
      token: schemas.pushToken.token
      sourceType: Joi.string().optional().valid [
        'android', 'ios', 'ios-fcm', 'web', 'web-fcm'
      ]
    , {presence: 'required'}

    if valid.error
      router.throw
        status: 400
        info: valid.error.message

    Promise.all [
      User.updateById userId, {
        hasPushToken: true
      }

      PushToken.upsert {
        userId: userId
        token: token
        sourceType: sourceType
        appKey: appKey
        deviceId: deviceId
      }
      .then ->
        PushNotificationService.subscribeToAllTopicsByUser user, {
          language
          appKey
          deviceId
        }
    ]


  updateByToken: ({token, language, deviceId}, {user, appKey}) ->
    userId = user.id

    Promise.all [
      User.updateById userId, {
        hasPushToken: true
      }
      PushToken.getAllByToken token
      .then (pushTokens) ->
        _.map pushTokens, PushToken.deleteByPushToken
        PushToken.upsert {
          token, deviceId, appKey
          userId: user.id
          sourceType: pushTokens?[0]?.sourceType or 'android'
        }
      .then ->
        Promise.all [
          PushNotificationService.subscribeToAllTopicsByUser user, {
            language
            appKey
            deviceId
          }
          PushNotificationService.migratePushTopicsByUserId user.id, {
            token
            appKey
            deviceId
          }
        ]
    ]
    .then ->
      null


module.exports = new PushTokensCtrl()
