_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

ONE_DAY_S = 3600 * 24

defaultTrade = (trade) ->
  unless trade?
    return null

  trade.sendItemKeys = JSON.stringify trade.sendItemKeys
  trade.receiveItemKeys = JSON.stringify trade.receiveItemKeys

  _.assign {
    id: cknex.getTimeUuid()
    sendItemKeys: []
    receiveItemKeys: []
    status: 'pending'
    expireTime: null
  }, trade

defaultTradeOutput = (trade) ->
  unless trade?
    return null

  trade.sendItemKeys = try
    JSON.parse trade.sendItemKeys
  catch error
    []

  trade.receiveItemKeys = try
    JSON.parse trade.receiveItemKeys
  catch error
    []

  trade.time = trade.id.getDate()
  trade


tables = [
  {
    name: 'trades_by_toId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      fromId: 'uuid'
      toId: 'uuid'
      expireTime: 'timestamp'
      sendItemKeys: 'text' # json
      receiveItemKeys: 'text' # json
      status: 'text'
    primaryKey:
      partitionKey: ['toId']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'trades_by_fromId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      fromId: 'uuid'
      toId: 'uuid'
      expireTime: 'timestamp'
      sendItemKeys: 'text' # json
      receiveItemKeys: 'text' # json
      status: 'text'
    primaryKey:
      partitionKey: ['fromId']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'trades_by_id'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      fromId: 'uuid'
      toId: 'uuid'
      expireTime: 'timestamp'
      sendItemKeys: 'text' # json
      receiveItemKeys: 'text' # json
      status: 'text'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
]

class TradeModel
  SCYLLA_TABLES: tables

  upsert: (trade, {ttl} = {}) ->
    trade = defaultTrade trade

    ttl ?= ONE_DAY_S

    trade.expireTime = new Date Date.now() + ttl * 1000

    Promise.all [
      cknex().update 'trades_by_toId'
      .set _.omit trade, ['toId', 'id']
      .where 'toId', '=', trade.toId
      .andWhere 'id', '=', trade.id
      .usingTTL ttl
      .run()

      cknex().update 'trades_by_fromId'
      .set _.omit trade, ['fromId', 'id']
      .where 'fromId', '=', trade.fromId
      .andWhere 'id', '=', trade.id
      .usingTTL ttl
      .run()

      cknex().update 'trades_by_id'
      .set _.omit trade, ['id']
      .where 'id', '=', trade.id
      .usingTTL ttl
      .run()
    ]
    .then ->
      trade

  getById: (id) ->
    cknex().select '*'
    .from 'trades_by_id'
    .where 'id', '=', id
    .run {isSingle: true}
    .then defaultTradeOutput

  getAllByToId: (toId, {limit} = {}) ->
    cknex().select '*'
    .from 'trades_by_toId'
    .where 'toId', '=', toId
    .limit limit
    .run()
    .map defaultTradeOutput

  getAllByFromId: (fromId, {limit} = {}) ->
    cknex().select '*'
    .from 'trades_by_fromId'
    .where 'fromId', '=', fromId
    .limit limit
    .run()
    .map defaultTradeOutput

  # getAllByUserIds: (fromId, toId) ->
  #   r.table TRADES_TABLE
  #   .getAll fromId, {index: TRADE_FROM_ID_INDEX}
  #   .filter {toId}
  #   .run()
  #   .map defaultTrade

  deleteByTrade: (trade) ->
    Promise.all [
      cknex().delete()
      .from 'trades_by_toId'
      .where 'toId', '=', trade.toId
      .andWhere 'id', '=', trade.id
      .run()

      cknex().delete()
      .from 'trades_by_fromId'
      .where 'fromId', '=', trade.fromId
      .andWhere 'id', '=', trade.id
      .run()

      cknex().delete()
      .from 'trades_by_id'
      .where 'id', '=', trade.id
      .run()
    ]

  deleteById: (id) =>
    @getById id
    .then @deleteByTrade

  sanitize: _.curry (requesterId, trade) ->
    _.pick trade, [
      'id'
      'sendItemKeys'
      'sendItems'
      'receiveItemKeys'
      'receiveItems'
      'fromId'
      'toId'
      'from'
      'to'
      'status'
      'expireTime'
      'time'
    ]

module.exports = new TradeModel()
