_ = require 'lodash'
Joi = require 'joi'
Promise = require 'bluebird'
router = require 'exoid-router'
request = require 'request-promise'

PushToken = require '../models/push_token'
User = require '../models/user'
schemas = require '../schemas'
config = require '../config'

class PushTokensCtrl
  create: ({token, sourceType}, {user}) ->
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

    PushToken.getByToken token
    .then (sameToken) ->
      if sameToken
        router.throw
          status: 400
          info: 'pushToken exists'
          ignoreLog: true

      Promise.all [
        User.updateById userId, {
          hasPushToken: true
        }
        PushToken.create {
          userId: userId
          token: token
          sourceType: sourceType
        }
        .then PushToken.sanitizePublic
      ]


  updateByToken: ({token}, {user}) ->
    userId = user.id

    updateSchema =
      userId: schemas.user.id

    diff = {userId}
    updateValid = Joi.validate diff, updateSchema

    if updateValid.error
      router.throw status: 400, info: updateValid.error.message

    Promise.all [
      User.updateById userId, {
        hasPushToken: true
      }
      PushToken.updateByToken token, diff
    ]
    .then ->
      null

  subscribeToTopic: ({token, topic}, {user}) ->
    base = 'https://iid.googleapis.com/iid/v1'
    request "#{base}/#{token}/rel/topics/#{topic}", {
      json: true
      method: 'POST'
      headers:
        'Authorization': "key=#{config.GOOGLE_API_KEY}"
      body: {}
    }


module.exports = new PushTokensCtrl()
