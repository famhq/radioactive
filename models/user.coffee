_ = require 'lodash'
uuid = require 'node-uuid'
PcgRandom = require 'pcg-random'

r = require '../services/rethinkdb'
UserData = require './user_data'
schemas = require '../schemas'
config = require '../config'

USERS_TABLE = 'users'
USERNAME_INDEX = 'username'
PUSH_TOKEN_INDEX = 'pushToken'

# TODO: migrate to scylla/cassandra
# users_by_id
# users_by_username
# probably means dropping push_token index

defaultUser = (user) ->
  unless user?
    return null

  _.defaults user, {
    id: uuid.v4()
    joinTime: new Date()
    username: null
    name: null
    isMember: 0 # 1 if yes
    hasPushToken: false
    lastActiveIp: null
    lastActiveTime: new Date()
    country: 'us'
    language: 'en'
    counters: {}
    flags: {}
  }

class UserModel
  RETHINK_TABLES: [
    {
      name: USERS_TABLE
      indexes: [
        {name: USERNAME_INDEX}
        {name: PUSH_TOKEN_INDEX, fn: (row) ->
          [row('hasPushToken'), row('id')]}
      ]
    }
  ]

  getById: (id) ->
    r.table USERS_TABLE
    .get id
    .run()
    .then defaultUser

  getLastActiveByIds: (ids) ->
    r.table USERS_TABLE
    .getAll r.args(ids)
    .filter r.row('username').ne null
    .orderBy r.desc 'lastActiveTime'
    .nth 0
    .default null
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

  getOrCreateVerifiedByPlayerTag: (playerTag) ->
    null
    # TODO

  updateById: (id, diff) ->
    r.table USERS_TABLE
    .get id
    .update diff
    .run()
    .then -> null

  updateSelf: (id, diff) ->
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
    unless user
      return null
    sanitizedUser = _.pick user, [
      'id'
      'username'
      'name'
      'avatarImage'
      'isMember'
      'isChatBanned'
      'isOnline'
      'flags'
      'data'
      'gameData'
      'followerCount'
      'embedded'
    ]
    sanitizedUser.flags = _.pick user.flags, [
      'isModerator', 'isDev', 'isChatBanned', 'isFoundingMember', 'isStar'
    ]
    sanitizedUser.data = _.pick user.data, [
      'presetAvatarId'
    ]
    sanitizedUser

module.exports = new UserModel()
