_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
knex = require '../services/knex'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

SIX_HOURS_S = 3600 * 6

defaultClashRoyalePlayer = (player) ->
  unless player?
    return null

  player.data = if player.data then JSON.parse player.data else {}
  player

class ClashRoyalePlayerBaseModel
  TABLE_NAME: 'players_by_id'

  constructor: ->
    @SCYLLA_TABLES = [
      {
        name: @TABLE_NAME
        fields:
          id: 'text'
          data: 'text'
          lastUpdateTime: 'timestamp'
          lastQueuedTime: 'timestamp'
        primaryKey:
          partitionKey: ['id']
          clusteringColumns: null
      }
      {
        name: 'auto_refresh_playerIds'
        fields:
          bucket: 'text'
          # playerIds overwhelmingly start with '2', but the last character is
          # evenly distributed
          reversedPlayerId: 'text'
          playerId: 'text'
        primaryKey:
          partitionKey: ['bucket']
          clusteringColumns: ['reversedPlayerId']
      }
    ]

  batchUpsert: (players) =>
    chunks = cknex.chunkForBatch players
    Promise.all _.map chunks, (chunk) =>
      cknex.batchRun _.map chunk, (player) =>
        playerId = player.id
        @upsertById playerId, player, {skipRun: true}

  setAutoRefreshById: (id) ->
    reversedPlayerId = id.split('').reverse().join('')
    cknex().update 'auto_refresh_playerIds'
    .set 'playerId', id # refreshes ttl if it exists
    .where 'bucket', '=', reversedPlayerId.substr(0, 1)
    .where 'reversedPlayerId', '=', reversedPlayerId
    .usingTTL 3600 * 24 # 1 day
    .run()

  getAutoRefresh: (minReversedPlayerId) ->
    cknex().select '*'
    .where 'bucket', '=', minReversedPlayerId.substr(0, 1)
    .andWhere 'reversedPlayerId', '>', minReversedPlayerId
    .limit 100 # TODO: var
    .from 'auto_refresh_playerIds'
    .run()

  getById: (id, {preferCache} = {}) =>
    get = =>
      cknex().select '*'
      .where 'id', '=', id
      .from @TABLE_NAME
      .run {isSingle: true}
      .then defaultClashRoyalePlayer

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) =>
    cknex().select '*'
    .where 'id', 'in', ids
    .from @TABLE_NAME
    .run()
    .map defaultClashRoyalePlayer

  upsertById: (id, diff, {skipRun} = {}) =>
    # if @TABLE_NAME is 'players_by_id' and diff.data and not diff.data.trophies
    #   throw new Error 'player upsert missing trophies'

    table = _.find @SCYLLA_TABLES, {name: @TABLE_NAME}
    validKeys = _.filter _.keys(table.fields), (key) -> key isnt 'id'

    diff = _.pick diff, validKeys

    if typeof diff.data is 'object'
      diff.data = JSON.stringify diff.data

    q = cknex().update @TABLE_NAME
    .set diff
    .where 'id', '=', id

    if @TABLE_NAME is 'players_daily'
      q = q.usingTTL 3600 * 24 * 2 # 2 days

    if skipRun
      return q

    q.run()

  migrateAll: (order) =>
    start = Date.now()
    Promise.all [
      CacheService.get 'migrate_players_min_id5'
      .then (minId) =>
        minId ?= '0'
        knex('players').select '*'
        .where {updateFrequency: 'default'}
        .andWhere 'id', '>', minId
        .orderBy 'id', 'asc'
        .limit 125
        .then (players) =>
          # console.log 'players', players.length
          @batchUpsert players
          .catch (err) ->
            console.log err
          .then ->
            console.log 'time', Date.now() - start, minId
            CacheService.set 'migrate_players_min_id5', _.last(players).id

      CacheService.get 'migrate_players_max_id6'
      .then (maxId) =>
        maxId ?= 'ZZZZZZZZZZZZZZZZZZZZZ'
        knex('players').select '*'
        .where {updateFrequency: 'default'}
        .andWhere 'id', '<', maxId
        .orderBy 'id', 'desc'
        .limit 125
        .then (players) =>
          # console.log 'playersrev', players.length
          @batchUpsert players
          .catch (err) ->
            console.log err
          .then ->
            console.log 'timerev', Date.now() - start, maxId
            CacheService.set 'migrate_players_max_id6', _.last(players).id
    ]
    .then =>
      @migrateAll()

module.exports = ClashRoyalePlayerBaseModel
