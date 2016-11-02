_ = require 'lodash'
router = require 'exoid-router'
bcrypt = require 'bcrypt'
Joi = require 'joi'
Promise = require 'bluebird'

Auth = require '../models/auth'
User = require '../models/user'
schemas = require '../schemas'

BCRYPT_ROUNDS = 10

class AuthCtrl
  login: ->
    User.create {}
    .then (user) ->
      Auth.fromUserId user.id

  # Transform or Create user with email and password
  loginCode: ({code, username, password}) ->
    insecurePassword = password

    valid = Joi.validate {insecurePassword, code, username},
      insecurePassword: Joi.string().min(6).max(1000)
      code: Joi.string().min(6).max(1000)
      username: schemas.user.username
    , {presence: 'required'}

    if valid.error
      router.throw {status: 400, info: valid.error.message}

    User.getByCode code
    .tap (user) ->
      if user and user.password
        router.throw {status: 401, info: 'Password already set'}
      else if user
        User.getByUsername username
        .then (existingUser) ->
          if existingUser
            router.throw {status: 401, info: 'Username is taken'}

          Promise.promisify(bcrypt.hash)(insecurePassword, BCRYPT_ROUNDS)
          .then (password) ->
            User.updateById user.id, {username, password}
      else
        router.throw {status: 401, info: 'Invalid code'}

    .then (user) ->
      Auth.fromUserId user.id

  loginUsername: ({username, password}) ->
    insecurePassword = password

    valid = Joi.validate {insecurePassword, username},
      insecurePassword: Joi.string().min(6).max(1000)
      username: schemas.user.username
    , {presence: 'required'}

    if valid.error
      router.throw {status: 400, info: valid.error.message}

    User.getByUsername username
    .then (user) ->
      if user and user.password
        return Promise.promisify(bcrypt.compare)(
          insecurePassword
          user.password
        )
        .then (success) ->
          if success
            return user
          router.throw {status: 401, info: 'Incorrect password'}

      # Invalid auth mechanism used
      else if user
        router.throw {status: 401, info: 'Incorrect password'}

      # don't create user for just username login
      else
        router.throw {status: 401, info: 'Username not found'}

    .then (user) ->
      Auth.fromUserId user.id


module.exports = new AuthCtrl()
