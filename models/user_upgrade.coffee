_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
config = require '../config'

# ALTER TABLE starfire."user_upgrades_by_userId" ADD data text;

tables = [
  {
    name: 'user_upgrades_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      itemKey: 'text'
      upgradeType: 'text'
      data: 'text'
      expireTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId', 'itemKey']
  }
]

defaultUserUpgrade = (upgrade) ->
  unless upgrade?
    return null

  if upgrade.data
    upgrade.data = JSON.stringify upgrade.data
  else
    upgrade.data = ''

  upgrade

defaultUserUpgradeOutput = (upgrade) ->
  unless upgrade?
    return null

  if upgrade.data
    upgrade.data = try
      JSON.parse upgrade.data
    catch err
      {}

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
    userUpgrade = defaultUserUpgrade userUpgrade

    cknex().update 'user_upgrades_by_userId'
    .set _.omit userUpgrade, ['userId', 'groupId', 'itemKey']
    .where 'userId', '=', userUpgrade.userId
    .andWhere 'groupId', '=', userUpgrade.groupId
    .andWhere 'itemKey', '=', userUpgrade.itemKey
    .usingTTL ttl
    .run()

module.exports = new UserUpgradeModel()
