_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
GroupRole = require './group_role'
config = require '../config'

ONE_DAY_SECONDS = 3600 * 24
TEN_MINUTES_SECONDS = 60 * 10

defaultGroupUser = (groupUser) ->
  unless groupUser?
    return null

  _.defaults groupUser, {
    time: new Date()
  }

tables = [
  {
    name: 'group_users_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      roleIds: {type: 'set', subType: 'uuid'}
      data: 'text'
      time: 'timestamp'
    primaryKey:
      # a little uneven since some groups will have a lot of users, but each
      # row is small
      partitionKey: ['groupId']
      clusteringColumns: ['userId']
  }
  {
    name: 'group_users_by_userId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      roleIds: {type: 'set', subType: 'uuid'}
      data: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId']
  }
  {
    name: 'group_users_xp_counter_by_userId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      xp: 'counter'
      level: 'counter'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId']
  }
]

class GroupUserModel
  SCYLLA_TABLES: tables

  upsert: (groupUser) ->
    groupUser = defaultGroupUser groupUser

    Promise.all [
      cknex().update 'group_users_by_groupId'
      .set _.omit groupUser, ['userId', 'groupId']
      .where 'groupId', '=', groupUser.groupId
      .andWhere 'userId', '=', groupUser.userId
      .run()

      cknex().update 'group_users_by_userId'
      .set _.omit groupUser, ['userId', 'groupId']
      .where 'userId', '=', groupUser.userId
      .andWhere 'groupId', '=', groupUser.groupId
      .run()
    ]
    .then ->
      groupUser
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_USER_USER_ID
      cacheKey = "#{prefix}:#{groupUser.userId}"
      CacheService.deleteByKey cacheKey
      categoryPrefix = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY
      categoryCacheKey = "#{categoryPrefix}:#{groupUser.userId}"
      CacheService.deleteByCategory categoryCacheKey

  addRoleIdByGroupUser: (groupUser, roleId) ->
    Promise.all [
      cknex().update 'group_users_by_groupId'
      .add 'roleIds', [[roleId]]
      .where 'groupId', '=', groupUser.groupId
      .andWhere 'userId', '=', groupUser.userId
      .run()

      cknex().update 'group_users_by_userId'
      .add 'roleIds', [[roleId]]
      .where 'userId', '=', groupUser.userId
      .andWhere 'groupId', '=', groupUser.groupId
      .run()
    ]
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_USER_USER_ID
      cacheKey = "#{prefix}:#{groupUser.userId}"
      CacheService.deleteByKey cacheKey
      categoryPrefix = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY
      categoryCacheKey = "#{categoryPrefix}:#{groupUser.userId}"
      CacheService.deleteByCategory categoryCacheKey

  removeRoleIdByGroupUser: (groupUser, roleId) ->
    Promise.all [
      cknex().update 'group_users_by_groupId'
      .remove 'roleIds', [roleId]
      .where 'groupId', '=', groupUser.groupId
      .andWhere 'userId', '=', groupUser.userId
      .run()

      cknex().update 'group_users_by_userId'
      .remove 'roleIds', [roleId]
      .where 'userId', '=', groupUser.userId
      .andWhere 'groupId', '=', groupUser.groupId
      .run()
    ]
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_USER_USER_ID
      cacheKey = "#{prefix}:#{groupUser.userId}"
      CacheService.deleteByKey cacheKey
      categoryPrefix = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY
      categoryCacheKey = "#{categoryPrefix}:#{groupUser.userId}"
      CacheService.deleteByCategory categoryCacheKey

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'group_users_by_groupId'
    .where 'groupId', '=', groupId
    .run()

  # TODO: should keep track of this in separate counter table since this can be
  # slow
  getCountByGroupId: (groupId, {preferCache} = {}) ->
    get = ->
      cknex().select()
      .count '*'
      .from 'group_users_by_groupId'
      .where 'groupId', '=', groupId
      .run {isSingle: true}
      .then (response) ->
        response?.count or 0


    if preferCache
      cacheKey = "#{CacheService.PREFIXES.GROUP_USER_COUNT}:#{groupId}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: TEN_MINUTES_SECONDS
      }
    else
      get()


  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'group_users_by_userId'
    .where 'userId', '=', userId
    .run()

  getByGroupIdAndUserId: (groupId, userId) ->
    cknex().select '*'
    .from 'group_users_by_groupId'
    .where 'groupId', '=', groupId
    .andWhere 'userId', '=', userId
    .run {isSingle: true}
    .then (groupUser) ->
      # so roles can still be embedded
      groupUser or {groupId}

  getXpByGroupIdAndUserId: (groupId, userId) ->
    cknex().select '*'
    .from 'group_users_xp_counter_by_userId'
    .where 'groupId', '=', groupId
    .andWhere 'userId', '=', userId
    .run {isSingle: true}
    .then (groupUser) ->
      groupUser?.xp or 0

  getTopByGroupId: (groupId) ->
    prefix = CacheService.STATIC_PREFIXES.GROUP_LEADERBOARD
    key = "#{prefix}:#{groupId}"
    CacheService.leaderboardGet key
    .then (results) ->
      _.map _.chunk(results, 2), ([userId, xp], i) ->
        {
          rank: i + 1
          groupId
          userId
          xp: parseInt xp
        }

  incrementXpByGroupIdAndUserId: (groupId, userId, amount) ->
    Promise.all [
      cknex().update 'group_users_xp_counter_by_userId'
      .increment 'xp', amount
      .where 'groupId', '=', groupId
      .andWhere 'userId', '=', userId
      .run()

      prefix = CacheService.STATIC_PREFIXES.GROUP_LEADERBOARD
      key = "#{prefix}:#{groupId}"
      CacheService.leaderboardIncrement key, userId, amount
    ]

  deleteByGroupIdAndUserId: (groupId, userId) ->
    Promise.all [
      cknex().delete()
      .from 'group_users_by_groupId'
      .where 'userId', '=', userId
      .andWhere 'groupId', '=', groupId
      .run()

      cknex().delete()
      .from 'group_users_by_userId'
      .where 'groupId', '=', groupId
      .andWhere 'userId', '=', userId
      .run()
    ]

  hasPermissionByGroupIdAndUser: (groupId, user, permissions, options) =>
    options ?= {}
    {channelId} = options

    @getByGroupIdAndUserId groupId, user.id
    .then (groupUser) =>
      groupUser or= {}
      GroupRole.getAllByGroupId groupId
      .then (roles) ->
        everyoneRole = _.find roles, {name: 'everyone'}
        groupUserRoles = _.map groupUser.roleIds, (roleId) ->
          _.find roles, {roleId}
        if everyoneRole
          groupUserRoles = groupUserRoles.concat everyoneRole
        groupUser.roles = groupUserRoles
        groupUser
      .then =>
        @hasPermission {
          meGroupUser: groupUser
          permissions: permissions
          channelId: channelId
          me: user
        }

  hasPermission: ({meGroupUser, me, permissions, channelId}) ->
    isGlobalModerator = false#me?.flags?.isModerator # FIXME FIXME
    isGlobalModerator or _.every permissions, (permission) ->
      _.find meGroupUser?.roles, (role) ->
        channelPermissions = channelId and role.channelPermissions?[channelId]
        globalPermissions = role.globalPermissions
        permissions = _.defaults(
          channelPermissions, globalPermissions, config.DEFAULT_PERMISSIONS
        )
        permissions[permission]


module.exports = new GroupUserModel()
