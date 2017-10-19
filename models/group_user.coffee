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
      roleId: 'uuid'
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
      roleId: 'uuid'
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

  # migrateAll: (order) =>
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_user_groups_min_id5'
  #     .then (minId) =>
  #       minId ?= '0'
  #       r.table 'group_users'
  #       .between minId, 'ZZZZ', {index: 'userId'}
  #       .orderBy {index: r.asc('userId')}
  #       .limit 500
  #       .then (userGroups) =>
  #         Promise.map userGroups, ({groupId, userId, time}) =>
  #           if groupId and userId
  #             @upsert {
  #               groupId: groupId
  #               userId: userId
  #               time: time
  #             }
  #           else
  #             # console.log 'skip', groupId, userId
  #             Promise.resolve null
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'time', Date.now() - start, minId, _.last(userGroups).userId
  #           CacheService.set 'migrate_user_groups_min_id5', _.last(userGroups).userId
  #
  #
  #     CacheService.get 'migrate_user_groups_max_id5'
  #     .then (maxId) =>
  #       maxId ?= 'ZZZZ'
  #       r.table 'group_users'
  #       .between '0000', maxId, {index: 'userId'}
  #       .orderBy {index: r.desc('userId')}
  #       .limit 500
  #       .then (userGroups) =>
  #         Promise.map userGroups, ({groupId, userId, time}) =>
  #           if groupId and userId
  #             @upsert {
  #               groupId: groupId
  #               userId: userId
  #               time: time
  #             }
  #           else
  #             # console.log 'skip', groupId, userId
  #             Promise.resolve null
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'time', Date.now() - start, maxId, _.last(userGroups).userId
  #           CacheService.set 'migrate_user_groups_max_id5', _.last(userGroups).userId
  #       ]
  #   .then =>
  #     @migrateAll()


module.exports = new GroupUserModel()
