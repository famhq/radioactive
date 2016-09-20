_ = require 'lodash'

Auth = require '../models/auth'
User = require '../models/user'

class AuthCtrl
  login: ->
    User.create {}
    .then (user) ->
      Auth.fromUserId user.id


module.exports = new AuthCtrl()
