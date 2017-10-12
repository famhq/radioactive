_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
Promise = require 'bluebird'
shortid = require 'shortid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

SIX_HOURS_S = 3600 * 6

###
CREATE KEYSPACE clash_royale WITH replication = {
  'class': 'NetworkTopologyStrategy', 'datacenter1': '3'
} AND durable_writes = true;

- may need to change pk to (playerId, bucket) where bucket is some amount
 of time that keeps partition size to < 100mb.
- 1 match = ~10kb. 10,000 matches = 100mb.
- if we do that, we need to query with both the playerId AND bucket to just
  get 1 partition's worth
###

tables = [
  {
    name: 'matches_by_playerId'
    fields:
      playerId: 'text'
      time: 'timestamp'
      gameType: 'text'
      arena: 'int'
      league: 'int'
      data: 'text'
    primaryKey:
      partitionKey: ['playerId']
      clusteringColumns: ['time']
    withClusteringOrderBy: ['time', 'desc']
  }
]

defaultClashRoyaleMatch = (clashRoyaleMatch) ->
  unless clashRoyaleMatch?
    return null

  try
    clashRoyaleMatch.data = JSON.parse(
      clashRoyaleMatch.data.replace(/\\/g, '').replace(/^"+|"+$/g, '')
    )
  catch

  clashRoyaleMatch

class ClashRoyaleMatchModel
  SCYLLA_TABLES: tables

  batchCreate: (clashRoyaleMatches) ->
    matches = _.flatten _.map clashRoyaleMatches, (match) ->
      playerIds = match.winningPlayerIds.concat(
        match.losingPlayerIds, match.drawPlayerIds
      )
      _.map playerIds, (playerId) ->
        _.pickBy {
          playerId: playerId
          gameType: match.type
          arena: match.arena
          league: match.league
          data: JSON.stringify match.data
          time: match.time
        }, (val) -> val?
    # partitionChunks = cknex.chunkForBatchByPartition matches, 'playerId'
    chunks = cknex.chunkForBatch matches
    Promise.all _.map chunks, (chunk) ->
      cknex.batchRun _.map chunk, (match) ->
        cknex().insert match
        .usingTTL 3600 * 24 * 30 # 1 month
        .into 'matches_by_playerId'

  getAllByPlayerId: (playerId, {limit, cursor} = {}) ->
    limit ?= 10

    (if cursor
      CacheService.getCursor cursor
    else
      Promise.resolve null)
    .then (cursorValue) ->
      cknex().select '*'
      .where 'playerId', '=', playerId
      # .limit limit
      .from 'matches_by_playerId'
      .run {fetchSize: limit, pageState: cursorValue, returnPageState: true}
    .then ({rows, pageState}) ->
      (if pageState
        newCursor = shortid.generate()
        CacheService.setCursor newCursor, pageState
      else
        newCursor = null
        Promise.resolve null
      )
      .then ->
        Promise.props {
          rows: rows.map defaultClashRoyaleMatch
          cursor: newCursor
        }

  existsByPlayerIdAndTime: (playerId, time, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .where 'playerId', '=', playerId
      .andWhere 'time', '=', time
      .from 'matches_by_playerId'
      .run {isSingle: true}
      .then (match) ->
        if match
          true
        else
          null

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID_EXISTS
      key = "#{prefix}:#{playerId}:#{time}"
      CacheService.preferCache key, get, {
        expireSeconds: SIX_HOURS_S
        ignoreNull: true
      }
    else
      get()

  sanitize: _.curry (requesterId, clashRoyaleMatch) ->
    _.pick clashRoyaleMatch, [
      'id'
      'arena'
      'data'
      'time'
    ]

module.exports = new ClashRoyaleMatchModel()
