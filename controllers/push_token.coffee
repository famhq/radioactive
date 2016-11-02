_ = require 'lodash'
Joi = require 'joi'
Promise = require 'bluebird'
router = require 'exoid-router'

PushToken = require '../models/push_token'
User = require '../models/user'
schemas = require '../schemas'

class PushTokensCtrl
  create: ({token, sourceType}, {user}) ->
    userId = user.id
    valid = Joi.validate {userId, token, sourceType},
      userId: schemas.user.id.optional()
      token: schemas.pushToken.token
      sourceType: Joi.string().optional().valid ['android', 'ios']
    , {presence: 'required'}

    if valid.error
      throw new router.Error
        status: 400
        detail: valid.error.message

    PushToken.getByToken token
    .then (sameToken) ->
      if sameToken
        throw new router.Error
          status: 400
          detail: 'pushToken exists'

      Promise.all [
        User.updateSelf userId, {
          hasPushToken: true
        }
        PushToken.create
          userId: userId
          token: token
          sourceType: sourceType
        .then PushToken.sanitizePublic
      ]


  updateByToken: ({token}, {user}) ->
    userId = user.id

    updateSchema =
      userId: schemas.user.id

    diff = _.pick diff, _.keys(updateSchema)
    updateValid = Joi.validate diff, updateSchema

    if updateValid.error
      throw new router.Error status: 400, info: updateValid.error.message

    Promise.all [
      User.updateSelf userId, {
        hasPushToken: true
      }
      PushToken.updateByToken token, diff
    ]
    .then ->
      null


module.exports = new PushTokensCtrl()
