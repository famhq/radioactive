log = require 'loga'

Auth = require '../models/auth'
User = require '../models/user'

class AuthService
  middleware: (req, res, next) ->
    # set req.user if authed
    accessToken = req.query?.accessToken

    unless accessToken?
      return next()

    Auth.userIdFromAccessToken accessToken
    .then User.getById
    .then (user) ->
      if not user?
        next()
      else
        # Authentication successful
        req.user = user
        next()
    .catch (err) ->
      log.warn err
      next()

module.exports = new AuthService()
