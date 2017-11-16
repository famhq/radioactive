_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'items_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      name: 'text'
      key: 'text'
      rarity: 'text'
      circulationLimit: 'int'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['key']
  }
  {
    name: 'items_by_key'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      name: 'text'
      key: 'text'
      rarity: 'text'
      circulationLimit: 'int'
    primaryKey:
      partitionKey: ['key']
  }
  {
    name: 'items_counter_by_key'
    keyspace: 'starfire'
    fields:
      key: 'text'
      level: 'int'
      circulating: 'counter'
    primaryKey:
      partitionKey: ['key']
      clusteringColumns: ['level']
  }
]

defaultItem = (item) ->
  unless item?
    return null
  item

class ItemModel
  SCYLLA_TABLES: tables

  batchUpsert: (items) =>
    Promise.map items, (item) =>
      @upsert item, {skipRun: true}

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'items_by_groupId'
    .where 'groupId', '=', groupId
    .run()

  getAll: ->
    cknex().select '*'
    .from 'items_by_groupId'
    .run()

  getByKey: (key) ->
    cknex().select '*'
    .from 'items_by_key'
    .where 'key', '=', key
    .run {isSingle: true}

  batchIncrementCirculatingByItemKeys: (itemKeys) =>
    counts = _.countBy itemKeys
    queries = _.map counts, (count, itemKey) =>
      level = 1
      @incrementCirculatingByKeyAndLevel itemKey, level, count, {skipRun: true}

    cknex.batchRun queries

  incrementCirculatingByKeyAndLevel: (key, level, amount, {skipRun} = {}) ->
    q = cknex().update 'items_counter_by_key'
    .increment 'circulating', amount
    .where 'key', '=', key
    .andWhere 'level', '=', level

    if skipRun
      q
    else
      q.run()

  upsert: (item, {skipRun} = {}) ->
    item = defaultItem item

    Promise.all [
      cknex().update 'items_by_groupId'
      .set _.omit item, ['groupId', 'key']
      .where 'groupId', '=', item.groupId
      .andWhere 'key', '=', item.key
      .run()

      cknex().update 'items_by_key'
      .set _.omit item, ['key']
      .where 'key', '=', item.key
      .run()
    ]

module.exports = new ItemModel()
