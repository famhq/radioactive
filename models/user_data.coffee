_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
schemas = require '../schemas'

USER_DATA_TABLE = 'user_data'
USER_ID_INDEX = 'userId'

defaultUserData = (userData) ->
  # unless userData?
  #   return {}

  _.defaults userData, {
    id: uuid.v4()
    userId: null
    followingIds: []
    followerIds: []
    blockedUserIds: []
    groupInvitedIds: []
    groupIds: []
    unreadGroupInvites: 0
  }

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
    .then (userData) ->
      _.defaults {userId}, userData

  upsertByUserId: (userId, diff) ->
    r.table USER_DATA_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .nth 0
    .default null
    .do (userData) ->
      r.branch(
        userData.eq null

        r.table USER_DATA_TABLE
        .insert defaultUserData _.defaults(_.clone(diff), {userId})

        r.table USER_DATA_TABLE
        .getAll userId, {index: USER_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
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
