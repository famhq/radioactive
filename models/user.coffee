_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
jwt = require 'jsonwebtoken'
PcgRandom = require 'pcg-random'
randomstring = require 'randomstring'

r = require '../services/rethinkdb'
UserData = require './user_data'
schemas = require '../schemas'
config = require '../config'

USERS_TABLE = 'users'
USERNAME_INDEX = 'username'
# invite codes
CODE_INDEX = 'code'
NUMERIC_ID_INDEX = 'numericId'
FACEBOOK_ID_INDEX = 'facebookId'
IS_MEMBER_INDEX = 'isMember'
LAST_ACTIVE_TIME_INDEX = 'lastActiveTime'

defaultUser = (user) ->
  unless user?
    return null

  _.assign {
    id: uuid.v4()
    numericId: null
    joinTime: new Date()
    facebookId: null
    username: null
    name: null
    code: null
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
        {name: NUMERIC_ID_INDEX}
        {name: CODE_INDEX}
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

  getByCode: (code) ->
    unless code
      return null

    r.table USERS_TABLE
    .getAll code, {index: CODE_INDEX}
    .nth(0)
    .default(null)
    .run()
    .then defaultUser

  generateCode: ->
    randomstring.generate 12

  getAllByUsername: (username, {limit} = {}) ->
    limit ?= 10

    return r.table USERS_TABLE
    # HACK to get indexed search to work
    .between username, username + 'z', {index: USERNAME_INDEX}
    .limit limit
    .run()
    .map defaultUser

  getCardCode: (user) ->
    random = new PcgRandom config.PCG_SEED
    i = 1
    while i < user.numericId
      random.integer config.CARD_CODE_MAX_LENGTH
      i += 1
    random.integer config.CARD_CODE_MAX_LENGTH

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

  convertToMember: (user) ->
    r.table USERS_TABLE
    .orderBy r.desc {index: NUMERIC_ID_INDEX}
    .nth 0
    .default null
    .pluck ['numericId']
    .do ({numericId}) ->
      r.table USERS_TABLE
      .get user.id
      .update {numericId: r.add(numericId, 1)}
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
      'isMember'
      'flags'
      'data'
      'embedded'
    ]
    sanitizedUser.flags = _.pick user.flags, [
      'isModerator', 'isDev', 'isChatBanned', 'isFoundingMember'
    ]
    sanitizedUser.data = _.pick user.data, [
      'presetAvatarId'
    ]
    sanitizedUser

module.exports = new UserModel()
