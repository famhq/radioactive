_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'user_upgrades_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      itemKey: 'text'
      upgradeType: 'text'
      expireTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId', 'itemKey']
  }
]

defaultUserUpgrade = (upgrade) ->
  unless upgrade?
    return null

  upgrade

defaultUserUpgradeOutput = (upgrade) ->
  unless upgrade?
    return null

  upgrade

class UserUpgradeModel
  SCYLLA_TABLES: tables
  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'user_upgrades_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultUserUpgradeOutput

  getByUserIdAndGroupIdAndItemKey: (userId, groupId, itemKey) ->
    cknex().select '*'
    .from 'user_upgrades_by_userId'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .andWhere 'itemKey', '=', itemKey
    .run {isSingle: true}
    .then defaultUserUpgradeOutput

  upsert: (userUpgrade, {ttl}) ->
    cknex().update 'user_upgrades_by_userId'
    .set _.omit userUpgrade, ['userId', 'groupId', 'itemKey']
    .where 'userId', '=', userUpgrade.userId
    .andWhere 'groupId', '=', userUpgrade.groupId
    .andWhere 'itemKey', '=', userUpgrade.itemKey
    .usingTTL ttl
    .run()

module.exports = new UserUpgradeModel()
