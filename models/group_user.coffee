_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'

ONE_DAY_SECONDS = 3600 * 24

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

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'group_users_by_groupId'
    .where 'groupId', '=', groupId
    .run()

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
      .andWhere 'userIdId', '=', userIdId
      .run()
    ]

  hasPermission: ({meGroupUser, me, permissions}) ->
    isGlobalModerator = false # FIXME me?.flags?.isModerator
    isGlobalModerator or _.every permissions, (permission) ->
      _.find meGroupUser?.roles, (role) ->
        role.globalPermissions.indexOf(permission) isnt -1


module.exports = new GroupUserModel()
