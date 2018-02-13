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
        keyspace: 'fortnite'
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
        keyspace: 'fortnite'
        fields:
          bucket: 'text'
          playerId: 'text'
        primaryKey:
          partitionKey: ['bucket']
          clusteringColumns: ['playerId']
      }
    ]

  batchUpsert: (players) =>
    chunks = cknex.chunkForBatch players
    Promise.all _.map chunks, (chunk) =>
      cknex.batchRun _.map chunk, (player) =>
        playerId = player.id
        @upsertById playerId, player, {skipRun: true}

  setAutoRefreshById: (id) ->
    playerId = id.split('').reverse().join('')
    cknex('fortnite').update 'auto_refresh_playerIds'
    .set 'playerId', id # refreshes ttl if it exists
    .where 'bucket', '=', playerId.substr(0, 1)
    .where 'playerId', '=', playerId
    .usingTTL 3600 * 24 # 1 day
    .run()

  getIsAutoRefreshById: (id) ->
    unless id
      return Promise.resolve null
    playerId = id.split('').reverse().join('')
    cknex('fortnite').select '*'
    .where 'bucket', '=', playerId.substr(0, 1)
    .andWhere 'playerId', '=', playerId
    .from 'auto_refresh_playerIds'
    .run {isSingle: true}

  getAutoRefresh: (minPlayerId) ->
    cknex('fortnite').select '*'
    .where 'bucket', '=', minPlayerId.substr(0, 1)
    .andWhere 'playerId', '>', minPlayerId
    .limit 1000 # TODO: var
    .from 'auto_refresh_playerIds'
    .run()

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex('fortnite').select '*'
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
    # maybe fixes crashing scylla? cache hits goes up to 500k
    ids = _.take ids, 200
    cknex('fortnite').select '*'
    .where 'id', 'in', ids
    .from 'players_by_id'
    .run()
    .map defaultClashRoyalePlayer

  upsertById: (id, diff, {skipRun} = {}) =>
    console.log 'ups', id, diff
    table = _.find @SCYLLA_TABLES, {name: 'players_by_id'}
    validKeys = _.filter _.keys(table.fields), (key) -> key isnt 'id'

    diff = _.pick diff, validKeys

    if typeof diff.data is 'object'
      diff.data = JSON.stringify diff.data

    console.log diff

    q = cknex('fortnite').update 'players_by_id'
    .set diff
    .where 'id', '=', id

    if skipRun
      return q

    q.run()

module.exports = new ClashRoyalePlayerModel()
