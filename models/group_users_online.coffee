_ = require 'lodash'
Promise = require 'bluebird'

config = require '../config'
cknex = require '../services/cknex'
CacheService = require '../services/cache'

FIFTEEN_MINUTES_SECONDS = 60 * 15


tables = [
  {
    name: 'group_users_online'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['userId']
  }
]

class GroupUsersOnline
  SCYLLA_TABLES: tables

  upsert: (groupUsersOnline) ->
    q = cknex().update 'group_users_online'
    .set {lastUpdateTime: new Date()}
    .where 'userId', '=', groupUsersOnline.userId
    .andWhere 'groupId', '=', groupUsersOnline.groupId
    .usingTTL FIFTEEN_MINUTES_SECONDS
    .run()
    .then ->
      groupUsersOnline

  getCountByGroupId: (groupId) ->
    key = "#{CacheService.PREFIXES.GROUP_USERS_ONLINE}:#{groupId}"
    CacheService.preferCache key, ->
      cknex().select()
      .count '*'
      .from 'group_users_online'
      .where 'groupId', '=', groupId
      .run()
      .then (response) ->
        response?.count or 0
    , {expireSeconds: FIFTEEN_MINUTES_SECONDS}

module.exports = new GroupUsersOnline()
