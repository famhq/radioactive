_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

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
      q = cknex().update 'counter_by_playerId'
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
    cknex().update 'auto_refresh_playerIds'
    .set 'playerId', id # refreshes ttl if it exists
    .where 'bucket', '=', reversedPlayerId.substr(0, 1)
    .where 'reversedPlayerId', '=', reversedPlayerId
    .usingTTL 3600 * 24 # 1 day
    .run()

  getIsAutoRefreshById: (id) ->
    unless id
      return Promise.resolve null
    reversedPlayerId = id.split('').reverse().join('')
    cknex().select '*'
    .where 'bucket', '=', reversedPlayerId.substr(0, 1)
    .andWhere 'reversedPlayerId', '=', reversedPlayerId
    .from 'auto_refresh_playerIds'
    .run {isSingle: true}

  getAutoRefresh: (minReversedPlayerId) ->
    cknex().select '*'
    .where 'bucket', '=', minReversedPlayerId.substr(0, 1)
    .andWhere 'reversedPlayerId', '>', minReversedPlayerId
    .limit 1000 # TODO: var
    .from 'auto_refresh_playerIds'
    .run()

  getCountersByPlayerIdAndScaledTime: (playerId, scaledTime) ->
    cknex().select '*'
    .where 'playerId', '=', playerId
    .andWhere 'scaledTime', '=', scaledTime
    .from 'counter_by_playerId'
    .run()
    .map defaultClashRoyalePlayerCounter

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .where 'id', '=', id
      .from 'players_by_id'
      .run {isSingle: true}
      .then defaultClashRoyalePlayer

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) ->
    cknex().select '*'
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

    q = cknex().update 'players_by_id'
    .set diff
    .where 'id', '=', id

    if skipRun
      return q

    q.run()

  migrate: (playerId) ->
    # console.log 'migrate player'
    createGameType = (player, gameType) ->
      splits = player?.data?.splits?[gameType]
      if splits
        cknex().update 'counter_by_playerId'
        .increment 'wins', splits?.wins or 0
        .increment 'losses', splits?.losses or 0
        .increment 'draws', splits?.draws or 0
        .increment 'crownsEarned', splits?.crownsEarned or 0
        .increment 'crownsLost', splits?.crownsLost or 0
        .where 'playerId', '=', playerId
        .andWhere 'scaledTime', '=', 'all'
        .andWhere 'gameType', '=', gameType

    knex.table 'players'
    .first '*'
    .where {id: playerId}
    .then (player) ->
      if player and not player.data?.hasMigrated
        cknex.batchRun _.filter [
          createGameType player, 'PvP'
          createGameType player, '2v2'
          createGameType player, 'classicChallenge'
          createGameType player, 'grandChallenge'
        ]
        .then ->
          knex.table 'players'
          .where {id: playerId}
          .update {
            data: _.defaults {hasMigrated: true}, player.data
          }


  # migrateAll: (order) =>
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_players_min_id5'
  #     .then (minId) =>
  #       minId ?= '0'
  #       knex('players').select '*'
  #       .where {updateFrequency: 'default'}
  #       .andWhere 'id', '>', minId
  #       .orderBy 'id', 'asc'
  #       .limit 125
  #       .then (players) =>
  #         # console.log 'players', players.length
  #         @batchUpsert players
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'time', Date.now() - start, minId
  #           CacheService.set 'migrate_players_min_id5', _.last(players).id
  #
  #     CacheService.get 'migrate_players_max_id6'
  #     .then (maxId) =>
  #       maxId ?= 'ZZZZZZZZZZZZZZZZZZZZZ'
  #       knex('players').select '*'
  #       .where {updateFrequency: 'default'}
  #       .andWhere 'id', '<', maxId
  #       .orderBy 'id', 'desc'
  #       .limit 125
  #       .then (players) =>
  #         # console.log 'playersrev', players.length
  #         @batchUpsert players
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'timerev', Date.now() - start, maxId
  #           CacheService.set 'migrate_players_max_id6', _.last(players).id
  #   ]
  #   .then =>
  #     @migrateAll()

module.exports = new ClashRoyalePlayerModel()
