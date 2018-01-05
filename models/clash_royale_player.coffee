_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

SIX_HOURS_S = 3600 * 6

defaultClashRoyalePlayer = (player) ->
  unless player?
    return null

  player.data = if player.data then JSON.parse player.data else {}
  player

defaultClashRoyalePlayerCounter = (playerCounter) ->
  _.defaults {
    wins: parseInt playerCounter.wins
    losses: parseInt playerCounter.losses
    draws: parseInt playerCounter.draws
    crownsEarned: parseInt playerCounter.crownsEarned
    crownsLost: parseInt playerCounter.crownsLost
  }, playerCounter

class ClashRoyalePlayerModel
  TABLE_NAME: 'players_by_id'

  constructor: ->
    @SCYLLA_TABLES = [
      {
        name: 'players_by_id'
        keyspace: 'clash_royale'
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
        name: 'counter_by_playerId'
        keyspace: 'clash_royale'
        fields:
          playerId: 'text'
          scaledTime: 'text'
          gameType: 'text'
          wins: 'counter'
          losses: 'counter'
          draws: 'counter'
          crownsEarned: 'counter'
          crownsLost: 'counter'
        primaryKey:
          partitionKey: ['playerId']
          clusteringColumns: ['scaledTime', 'gameType']
      }
      {
        name: 'auto_refresh_playerIds'
        keyspace: 'clash_royale'
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

  batchUpsertCounterByMatches: (matches) ->
    playerIdCnt = {}

    mapCondition = ->
      [condition, playerIds, momentTime, gameType,
        crownsEarned, crownsLost] = arguments

      scaledTime = 'DAY-' + momentTime.format 'YYYY-MM-DD'
      _.forEach playerIds, (playerId, i) ->
        key = [playerId, scaledTime, gameType].join(',')
        allGameTypeKey = [playerId, scaledTime, 'all'].join(',')
        allTimeKey = [playerId, 'all', gameType].join(',')
        allKey = [playerId, 'all', 'all'].join(',')
        playerIdCnt[key] ?= {
          wins: 0, losses: 0, draws: 0, crownsEarned: 0, crownsLost: 0
        }
        playerIdCnt[key][condition] += 1
        playerIdCnt[key]['crownsEarned'] += crownsEarned
        playerIdCnt[key]['crownsLost'] += crownsLost

        playerIdCnt[allGameTypeKey] ?= {
          wins: 0, losses: 0, draws: 0, crownsEarned: 0, crownsLost: 0
        }
        playerIdCnt[allGameTypeKey][condition] += 1
        playerIdCnt[allGameTypeKey]['crownsEarned'] += crownsEarned
        playerIdCnt[allGameTypeKey]['crownsLost'] += crownsLost

        playerIdCnt[allTimeKey] ?= {
          wins: 0, losses: 0, draws: 0, crownsEarned: 0, crownsLost: 0
        }
        playerIdCnt[allTimeKey][condition] += 1
        playerIdCnt[allTimeKey]['crownsEarned'] += crownsEarned
        playerIdCnt[allTimeKey]['crownsLost'] += crownsLost

        playerIdCnt[allKey] ?= {
          wins: 0, losses: 0, draws: 0, crownsEarned: 0, crownsLost: 0
        }
        playerIdCnt[allKey][condition] += 1
        playerIdCnt[allKey]['crownsEarned'] += crownsEarned
        playerIdCnt[allKey]['crownsLost'] += crownsLost

    _.forEach matches, (match) ->
      gameType = match.type
      mapCondition(
        'wins', match.winningPlayerIds, match.momentTime, gameType,
        crownsEarned = match.winningCrowns, crownsLost = match.losingCrowns
      )
      mapCondition(
        'losses', match.losingPlayerIds, match.momentTime, gameType,
        crownsEarned = match.losingCrowns, crownsLost = match.winningCrowns
      )
      mapCondition(
        'draws', match.drawPlayerIds, match.momentTime, gameType,
        crownsEarned = match.winningCrowns, crownsLost = match.winningCrowns
      )

    countQueries = _.map playerIdCnt, (diff, key) ->
      [playerId, scaledTime, gameType] = key.split ','
      q = cknex('clash_royale').update 'counter_by_playerId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'playerId', '=', playerId
      .andWhere 'scaledTime', '=', scaledTime
      .andWhere 'gameType', '=', gameType

    cknex.batchRun countQueries

  batchUpsert: (players) =>
    chunks = cknex.chunkForBatch players
    Promise.all _.map chunks, (chunk) =>
      cknex.batchRun _.map chunk, (player) =>
        playerId = player.id
        @upsertById playerId, player, {skipRun: true}

  setAutoRefreshById: (id) ->
    reversedPlayerId = id.split('').reverse().join('')
    cknex('clash_royale').update 'auto_refresh_playerIds'
    .set 'playerId', id # refreshes ttl if it exists
    .where 'bucket', '=', reversedPlayerId.substr(0, 1)
    .where 'reversedPlayerId', '=', reversedPlayerId
    .usingTTL 3600 * 24 # 1 day
    .run()

  getIsAutoRefreshById: (id) ->
    unless id
      return Promise.resolve null
    reversedPlayerId = id.split('').reverse().join('')
    cknex('clash_royale').select '*'
    .where 'bucket', '=', reversedPlayerId.substr(0, 1)
    .andWhere 'reversedPlayerId', '=', reversedPlayerId
    .from 'auto_refresh_playerIds'
    .run {isSingle: true}

  getAutoRefresh: (minReversedPlayerId) ->
    cknex('clash_royale').select '*'
    .where 'bucket', '=', minReversedPlayerId.substr(0, 1)
    .andWhere 'reversedPlayerId', '>', minReversedPlayerId
    .limit 1000 # TODO: var
    .from 'auto_refresh_playerIds'
    .run()

  getCountersByPlayerIdAndScaledTime: (playerId, scaledTime) ->
    cknex('clash_royale').select '*'
    .where 'playerId', '=', playerId
    .andWhere 'scaledTime', '=', scaledTime
    .from 'counter_by_playerId'
    .run()
    .map defaultClashRoyalePlayerCounter

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex('clash_royale').select '*'
      .where 'id', '=', id
      .from 'players_by_id'
      .run {isSingle: true}
      .then defaultClashRoyalePlayer
      .catch (err) ->
        console.log 'caught getbyid', id
        throw new Error ''

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) ->
    cknex('clash_royale').select '*'
    .where 'id', 'in', ids
    .from 'players_by_id'
    .run()
    .map defaultClashRoyalePlayer

  upsertById: (id, diff, {skipRun} = {}) =>
    table = _.find @SCYLLA_TABLES, {name: 'players_by_id'}
    validKeys = _.filter _.keys(table.fields), (key) -> key isnt 'id'

    diff = _.pick diff, validKeys

    if typeof diff.data is 'object'
      diff.data = JSON.stringify diff.data

    q = cknex('clash_royale').update 'players_by_id'
    .set diff
    .where 'id', '=', id

    if skipRun
      return q

    q.run()

module.exports = new ClashRoyalePlayerModel()
