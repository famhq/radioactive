_ = require 'lodash'
uuid = require 'node-uuid'
PcgRandom = require 'pcg-random'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
UserData = require './user_data'
schemas = require '../schemas'
config = require '../config'

USERS_TABLE = 'users'
USERNAME_INDEX = 'username'
PUSH_TOKEN_INDEX = 'pushToken'
SIX_HOURS_S = 3600 * 6

# TODO: migrate to scylla/cassandra
# users_by_id
# users_by_username
# probably means dropping push_token index

# store fire on user object

defaultUser = (user) ->
  unless user?
    return null

  _.defaults user, {
    id: uuid.v4()
    joinTime: new Date()
    username: null
    name: null
    isMember: 0 # 1 if yes
    fire: 0
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

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table USERS_TABLE
      .get "#{id}"
      .run()
      .then defaultUser

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.USER_ID}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

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

  updateById: (id, diff) ->
    r.table USERS_TABLE
    .get id
    .update diff
    .run()
    .tap ->
      cacheKey = "#{CacheService.PREFIXES.USER_ID}:#{id}"
      CacheService.deleteByKey cacheKey
    .then ->
      null

  addFireById: (id, amount) ->
    r.table USERS_TABLE
    .get id
    .update fire: r.row('fire').default(0).add(amount)
    .run()
    .tap ->
      cacheKey = "#{CacheService.PREFIXES.USER_ID}:#{id}"
      CacheService.deleteByKey cacheKey
    .then ->
      null

  subtractFireById: (id, amount) ->
    r.table USERS_TABLE
    .getAll id
    .filter r.row('fire').default(0).ge amount
    .update fire: r.row('fire').default(0).sub(amount)
    .run()
    .tap ->
      cacheKey = "#{CacheService.PREFIXES.USER_ID}:#{id}"
      CacheService.deleteByKey cacheKey

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
