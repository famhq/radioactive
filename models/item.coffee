_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
config = require '../config'

# types: sticker
#        consumable (send message, name badge, name color?)
# ALTER TABLE starfire."items_by_groupId" ADD type text;
# ALTER TABLE starfire."items_by_key" ADD type text;
# ALTER TABLE starfire."items_by_groupId" ADD data text;
# ALTER TABLE starfire."items_by_key" ADD data text;
# ALTER TABLE starfire."items_by_groupId" ADD tier text;
# ALTER TABLE starfire."items_by_key" ADD tier text;

tables = [
  {
    name: 'items_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      name: 'text'
      key: 'text'
      rarity: 'text'
      tier: 'text' # free / premium
      type: 'text'
      data: 'text'
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
      tier: 'text' # free / premium
      type: 'text'
      data: 'text'
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
  item = _.cloneDeep item
  item.data = JSON.stringify item.data
  _.defaults item, {
    type: 'sticker'
    tier: 'free'
  }

defaultItemOutput = (item) ->
  unless item?
    return null

  item.tier ?= 'base'
  item.data = try
    JSON.parse item.data
  catch err
    null
  item

class ItemModel
  SCYLLA_TABLES: tables

  batchUpsert: (items) =>
    Promise.map items, (item) =>
      @upsert item

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'items_by_groupId'
    .where 'groupId', '=', groupId
    .run()
    .map defaultItemOutput

  # not performant (grabs from all shards)
  # getAll: ->
  #   cknex().select '*'
  #   .from 'items_by_groupId'
  #   .run()

  getByKey: (key) ->
    cknex().select '*'
    .from 'items_by_key'
    .where 'key', '=', key
    .run {isSingle: true}
    .then defaultItemOutput

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

  upsert: (item) ->
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
