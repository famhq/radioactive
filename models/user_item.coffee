_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
config = require '../config'

# TOOD: rm itemLevel column in database (we calculate it from count now)
tables = [
  {
    name: 'user_items_counter_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      itemKey: 'text'
      # itemLevel: 'counter'
      count: 'counter'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['itemKey']
  }
]

defaultUserItem = (item) ->
  unless item?
    return null

  item

defaultUserItemOutput = (item) ->
  unless item?
    return null

  item.count = parseInt item.count
  item.itemLevel = _.find(config.ITEM_LEVEL_REQUIREMENTS, (req) ->
    item.count >= req.countRequired
  )?.level or 1

  item

class UserItemModel
  SCYLLA_TABLES: tables

  batchIncrementByItemKeysAndUserId: (itemKeys, userId) =>
    counts = _.countBy itemKeys
    @batchIncrementByCountsAndUserId counts, userId

  batchIncrementByCountsAndUserId: (counts, userId) =>
    queries = _.map counts, (count, itemKey) =>
      @incrementByItemKeyAndUserId itemKey, userId, count, {skipRun: true}

    cknex.batchRun queries

  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'user_items_counter_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultUserItemOutput
    .then (userItems) ->
      _.filter userItems, ({count}) -> Boolean count

  getAllKeysByUserId: (userId) ->
    cknex().select '*'
    .from 'user_items_counter_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultUserItemOutput
    .then (userItems) ->
      _.filter userItems, ({count}) -> Boolean count
    .map (item) -> item.itemKey

  getByUserIdAndItemKey: (userId, itemKey) ->
    cknex().select '*'
    .from 'user_items_counter_by_userId'
    .where 'userId', '=', userId
    .andWhere 'itemKey', '=', itemKey
    .run {isSingle: true}
    .then defaultUserItemOutput

  incrementLevelByItemKeyAndUserId: (itemKey, userId, count, {skipRun} = {}) ->
    cknex().update 'user_items_counter_by_userId'
    .increment 'itemLevel', count
    .where 'userId', '=', userId
    .andWhere 'itemKey', '=', itemKey
    .run()

  incrementByItemKeyAndUserId: (itemKey, userId, count, {skipRun} = {}) ->
    q = cknex().update 'user_items_counter_by_userId'
    .increment 'count', count
    .where 'userId', '=', userId
    .andWhere 'itemKey', '=', itemKey

    if skipRun
      q
    else
      q.run()

module.exports = new UserItemModel()
