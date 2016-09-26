_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
jwt = require 'jsonwebtoken'

r = require '../services/rethinkdb'
UserData = require './user_data'
schemas = require '../schemas'

USERS_TABLE = 'users'
USERNAME_INDEX = 'username'
FACEBOOK_ID_INDEX = 'facebookId'
IS_MEMBER_INDEX = 'isMember'
LAST_ACTIVE_TIME_INDEX = 'lastActiveTime'

defaultUser = (user) ->
  unless user?
    return null

  _.assign {
    id: uuid.v4()
    joinTime: new Date()
    facebookId: null
    username: null
    name: null
    isMember: 0 # 1 if yes
    lastActiveTime: new Date()
    counters: {}
    flags: {}
    preferredCategories: []
  }, user

class UserModel
  RETHINK_TABLES: [
    {
      name: USERS_TABLE
      indexes: [
        {name: USERNAME_INDEX}
        {name: FACEBOOK_ID_INDEX}
        {name: IS_MEMBER_INDEX}
        {name: LAST_ACTIVE_TIME_INDEX}
      ]
    }
  ]

  getById: (id) ->
    r.table USERS_TABLE
    .get id
    .run()
    .then defaultUser

  getByFacebookId: (facebookId) ->
    r.table USERS_TABLE
    .getAll facebookId, {index: FACEBOOK_ID_INDEX}
    .nth(0)
    .default(null)
    .run()
    .then defaultUser

  getByUsername: (username) ->
    r.table USERS_TABLE
    .getAll username, {index: USERNAME_INDEX}
    .nth(0)
    .default(null)
    .run()
    .then defaultUser

  getAllByUsername: (username, {limit} = {}) ->
    limit ?= 10

    return r.table USERS_TABLE
    # HACK to get indexed search to work
    .between username, username + 'z', {index: USERNAME_INDEX}
    .limit limit
    .run()
    .map defaultUser

  updateById: (id, diff) ->
    r.table USERS_TABLE
    .get id
    .update diff
    .run()
    .then -> null

  create: (user) ->
    user = defaultUser user

    r.table USERS_TABLE
    .insert user
    .run()
    .then ->
      user

  getUniqueUsername: (baseUsername, appendedNumber = 0) =>
    username = "#{baseUsername}".toLowerCase()
    username = if appendedNumber \
               then "#{username}#{appendedNumber}"
               else username
    @getByUsername username
    .then (existingUser) =>
      if appendedNumber > MAX_UNIQUE_USERNAME_ATTEMPTS
        null
      else if existingUser
        @getUniqueUsername baseUsername, appendedNumber + 1
      else
        username

  getDisplayName: (user) ->
    user?.username or user?.name or user?.kikUsername or 'anonymous'

  sanitize: _.curry (requesterId, user) ->
    _.pick user, _.keys schemas.user

  sanitizePublic: _.curry (requesterId, user) ->
    sanitizedUser = _.pick user, [
      'id'
      'username'
      'name'
      'avatarImage'
      'flags'
      'data'
      'embedded'
    ]
    sanitizedUser.flags = _.pick user.flags, [
      'isModerator', 'isDev', 'isChatBanned'
    ]
    sanitizedUser.data = _.pick user.data, [
      'presetAvatarId'
    ]
    sanitizedUser

module.exports = new UserModel()
