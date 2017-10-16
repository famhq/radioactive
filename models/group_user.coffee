_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

GROUP_ID_INDEX = 'groupId'
USER_ID_INDEX = 'userId'

ONE_DAY_SECONDS = 3600 * 24

defaultGroupUser = (groupUser) ->
  unless groupUser?
    return null

  if groupUser.groupId and groupUser.userId
    id = "#{groupUser.groupId}:#{groupUser.userId}"
  else
    id = uuid.v4()

  _.defaults groupUser, {
    id: id
    groupId: null
    userId: null
    roleId: null
    # globalPermissions:
    #   viewMessages: true
    #   createMessages: false
    #   deleteMessages: false
    #   manageChannels: false
    #   manageMembers: false
    #   manageRecords: false
    #   manageRoles: false
    #   manageSettings: false
    #   manageEvents: false
    # channelPermissions: {}
    time: new Date()
  }

GROUP_USERS_TABLE = 'group_users'

class GroupUserModel
  RETHINK_TABLES: [
    {
      name: GROUP_USERS_TABLE
      indexes: [
        {name: GROUP_ID_INDEX}
        {name: USER_ID_INDEX}
      ]
    }
  ]

  create: (groupUser) ->
    groupUser = defaultGroupUser groupUser

    r.table GROUP_USERS_TABLE
    .insert groupUser
    .run()
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_USER_USER_ID
      cacheKey = "#{prefix}:#{groupUser.userId}"
      CacheService.deleteByKey cacheKey
      categoryPrefix = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY
      categoryCacheKey = "#{categoryPrefix}:#{groupUser.userId}"
      CacheService.deleteByCategory categoryCacheKey
    .then ->
      groupUser

  getAllByGroupId: (groupId) ->
    r.table GROUP_USERS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()

  getAllByUserId: (userId, {preferCache} = {}) ->
    get = ->
      r.table GROUP_USERS_TABLE
      .getAll userId, {index: USER_ID_INDEX}
      .run()

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.GROUP_USER_USER_ID}:#{userId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  deleteByGroupIdAndUserId: (groupId, userId) ->
    r.table GROUP_USERS_TABLE
    .get "#{groupId}:#{userId}"
    .delete()
    .run()
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_USER_USER_ID
      cacheKey = "#{prefix}:#{userId}"
      CacheService.deleteByKey cacheKey

module.exports = new GroupUserModel()
