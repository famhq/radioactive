_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
log = require 'loga'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
schemas = require '../schemas'

USER_DATA_TABLE = 'user_data'
USER_ID_INDEX = 'userId'
ONE_HOUR_SECONDS = 3600
TEN_DAYS_SECONDS = 3600 * 24 * 10

defaultUserData = (userData) ->
  # unless userData?
  #   return {}

  _.assign {
    id: uuid.v4()
    userId: null
    followingIds: []
    followerIds: []
    blockedUserIds: []
    clashRoyaleDeckIds: []
  }, userData

class UserDataModel
  RETHINK_TABLES: [
    {
      name: USER_DATA_TABLE
      indexes: [
        {name: USER_ID_INDEX}
      ]
    }
  ]

  getById: (id) ->
    r.table USER_DATA_TABLE
    .get id
    .run()
    .then defaultUserData

  getByUserId: (userId) ->
    r.table USER_DATA_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserData

  upsertByUserId: (userId, diff) ->
    r.table USER_DATA_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .nth 0
    .default null
    .do (userData) ->
      r.branch(
        userData.eq null

        r.table USER_DATA_TABLE
        .insert defaultUserData _.defaults(diff, {userId})

        r.table USER_DATA_TABLE
        .getAll userId, {index: USER_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then ->
      null

  create: (userData) ->
    userData = defaultUserData userData

    r.table USER_DATA_TABLE
    .insert userData
    .run()
    .then ->
      userData

  sanitize: _.curry (requesterId, userData) ->
    _.pick userData, _.keys schemas.userData

module.exports = new UserDataModel()
