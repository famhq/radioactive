_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
schemas = require '../schemas'

class UserCtrl
  getMe: ({}, {user}) ->
    User.sanitize(null, user)

  updateMe: ({username}, {user}) ->
    router.assert {username}, {
      username: schemas.user.username
    }

    User.updateById(user.id, {username})
    .then -> null

module.exports = new UserCtrl()
