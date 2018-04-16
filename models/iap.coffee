_ = require 'lodash'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

tables = [
  {
    name: 'iap_by_platform'
    keyspace: 'starfire'
    fields:
      platform: 'text'
      key: 'text'
      name: 'text'
      priceCents: 'int'
      data: 'text'
    primaryKey:
      partitionKey: ['platform']
      clusteringColumns: ['key']
  }
]

defaultIap = (iap) ->
  unless iap?
    return null

  iap = _.cloneDeep iap

  if iap.data
    iap.data = JSON.stringify iap.data

  _.defaults iap, {
    platform: config.EMPTY_UUID
  }

defaultIapOutput = (iap) ->
  unless iap?
    return null

  iap.platform = "#{iap.platform}"

  iap

class IapModel
  SCYLLA_TABLES: tables

  batchUpsert: (iaps) =>
    Promise.map iaps, (iap) =>
      @upsert iap

  getAllByGroupId: (platform) ->
    platform ?= config.EMPTY_UUID

    cknex().select '*'
    .from 'iap_by_platform'
    .where 'platform', '=', platform
    .run()
    .map defaultIapOutput

  upsert: (iap) =>
    iap = defaultIap iap

    cknex().update 'iap_by_platform'
    .set _.omit iap, ['platform', 'key']
    .where 'platform', '=', iap.platform
    .andWhere 'key', '=', iap.key
    .run()

module.exports = new IapModel()
