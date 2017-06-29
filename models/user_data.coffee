_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
schemas = require '../schemas'

USER_DATA_TABLE = 'user_data'
USER_ID_INDEX = 'userId'
SIX_HOURS_SECONDS = 3600 * 6

defaultUserData = (userData) ->
  # unless userData?
  #   return {}

  id = userData?.userId or uuid.v4()

  _.defaults userData, {
    id: id
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

  getByUserId: (userId, {preferCache} = {}) ->
    get = ->
      r.table USER_DATA_TABLE
      .get userId
      .run()
      .then defaultUserData
      .then (userData) ->
        _.defaults {userId}, userData

    if preferCache
      key = "#{CacheService.PREFIXES.USER_DATA}:#{userId}"
      CacheService.preferCache key, get, {expireSeconds: SIX_HOURS_SECONDS}
    else
      get()

  upsertByUserId: (userId, diff) ->
    r.table USER_DATA_TABLE
    .get userId
    .replace (userData) ->
      r.branch(
        userData.eq null

        defaultUserData _.defaults(_.clone(diff), {userId})

        userData.merge diff
      )
    .run()
    .then ->
      key = "#{CacheService.PREFIXES.USER_DATA}:#{userId}"
      CacheService.deleteByKey key
      null


  sanitize: _.curry (requesterId, userData) ->
    _.pick userData, _.keys schemas.userData

module.exports = new UserDataModel()
