_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'
Promise = require 'bluebird'
shortid = require 'shortid'

knex = require '../services/knex'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

POSTGRES_MATCH_TABLE = 'matches_new'

SIX_HOURS_S = 3600 * 6

defaultPlayer =
  deckId: null
  crowns: null
  playerName: null
  playerTag: null
  clanName: null
  clanTag: null
  trophies: null

###
CREATE KEYSPACE clash_royale WITH replication = {
  'class': 'NetworkTopologyStrategy', 'datacenter1': '3'
} AND durable_writes = true;

CREATE TABLE clash_royale."matches_by_playerId" (
  "playerId" text,
  time timestamp,
  arena int,
  league int,
  data text,
  PRIMARY KEY ("playerId", time)
) WITH CLUSTERING ORDER BY (time DESC)

- may need to change pk to (playerId, bucket) where bucket is some amount
 of time that keeps partition size to < 100mb.
- 1 match = ~10kb. 10,000 matches = 100mb.
- if we do that, we need to query with both the playerId AND bucket to just
  get 1 partition's worth

CREATE TABLE clash_royale."counter_by_deckId_opponentCardId" (
  "deckId" text,
  "opponentCardId" text,
  "gameType" text,
  arena int,
  wins counter,
  draws counter,
  losses counter,
  PRIMARY KEY ("deckId", "gameType", arena, "opponentCardId")
)

CREATE TABLE clash_royale."counter_by_cardId" (
  "cardId" text,
  "gameType" text,
  arena int,
  wins counter,
  losses counter,
  draws counter,
  PRIMARY KEY ("cardId", "gameType", arena)
)

CREATE TABLE clash_royale."counter_by_deckId" (
  "deckId" text,
  "gameType" text,
  arena int,
  wins counter,
  losses counter,
  draws counter,
  PRIMARY KEY ("deckId", "gameType", arena)
)

###

fields = [
  {name: 'id', type: 'string', length: 100, index: 'primary'}
  {name: 'arena', type: 'integer', index: 'default'}
  {name: 'league', type: 'integer'}
  {name: 'teamPlayerIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'opponentPlayerIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'winningDeckIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'losingDeckIds', type: 'array', arrayType: 'text', index: 'gin'}
  {
    name: 'type', type: 'string', length: 50, index: 'default'
    defaultValue: 'PvP'
  }
  {name: 'winningCardIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'losingCardIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'data', type: 'json', defaultValue: defaultPlayer}
  {name: 'time', type: 'dateTime', index: 'default', defaultValue: new Date()}
]

defaultClashRoyaleMatchC = (clashRoyaleMatch) ->
  unless clashRoyaleMatch?
    return null

  try
    clashRoyaleMatch.data = JSON.parse clashRoyaleMatch.data
  catch

  clashRoyaleMatch

defaultClashRoyaleMatch = (clashRoyaleMatch) ->
  unless clashRoyaleMatch?
    return null

  clashRoyaleMatch = _.pick clashRoyaleMatch, _.map(fields, 'name')

  _.defaults clashRoyaleMatch, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

runMatchesByPlayerId = (matches) ->
  _.flatten _.map matches, (match) ->
    playerIds = match.teamPlayerIds.concat match.opponentPlayerIds
    _.map playerIds, (playerId) ->
      # batch isn't meant for performance, but we could groupBy playerId and
      #  batchRun (it helps performance some if used correctly)
      cknex().insert _.pickBy {
        playerId: playerId
        arena: match.arena
        league: match.league
        data: JSON.stringify match.data
        time: cknex.getTime match.time
      }, (val) -> val?
      .usingTTL 3600 * 24 * 30 # 1 month
      .into 'matches_by_playerId'
      .run()

runMatchesCounter = (matches) ->
  deckIdCnt = {}
  cardIdCnt = {}
  deckIdCardIdCnt = {}

  _.forEach matches, (match) ->
    gameType = match.type
    arena = if gameType is 'PvP' then match.arena else 0

    _.forEach match.winningCardIds, (cardId) ->
      key = [cardId, gameType, arena].join(',')
      cardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
      cardIdCnt[key].wins += 1
    _.forEach match.losingCardIds, (cardId) ->
      key = [cardId, gameType, arena].join(',')
      cardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
      cardIdCnt[key].losses += 1
    _.forEach match.drawCardIds, (cardId) ->
      key = [cardId, gameType, arena].join(',')
      cardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
      cardIdCnt[key].draws += 1

    _.forEach match.winningDeckIds, (deckId) ->
      deckKey = [deckId, gameType, arena].join(',')
      deckIdCnt[deckKey] ?= {wins: 0, losses: 0, draws: 0}
      deckIdCnt[deckKey].wins += 1
      _.forEach match.losingCardIds, (cardId) ->
        key = [deckId, gameType, arena, cardId].join(',')
        deckIdCardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
        deckIdCardIdCnt[key].wins += 1

    _.forEach match.losingDeckIds, (deckId) ->
      deckKey = [deckId, gameType, arena].join(',')
      deckIdCnt[deckKey] ?= {wins: 0, losses: 0, draws: 0}
      deckIdCnt[deckKey].losses += 1
      _.forEach match.winningCardIds, (cardId) ->
        key = [deckId, gameType, arena, cardId].join(',')
        deckIdCardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
        deckIdCardIdCnt[key].losses += 1

    _.forEach match.drawDeckIds, (deckId) ->
      deckKey = [deckId, gameType, arena].join(',')
      deckIdCnt[deckKey] ?= {wins: 0, losses: 0, draws: 0}
      deckIdCnt[deckKey].draws += 1
      _.forEach match.drawCardIds, (cardId) ->
        key = [deckId, gameType, arena, cardId].join(',')
        deckIdCardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
        deckIdCardIdCnt[key].draws += 1

  deckIdQueries = _.map deckIdCnt, (diff, key) ->
    [deckId, gameType, arena] = key.split ','
    q = cknex().update 'counter_by_deckId'
    _.forEach diff, (amount, key) ->
      q = q.increment key, amount
    q.where 'deckId', '=', deckId
    .andWhere 'gameType', '=', gameType
    .andWhere 'arena', '=', arena
    .run()

  cardIdQueries = _.map cardIdCnt, (diff, key) ->
    [cardId, gameType, arena] = key.split ','
    q = cknex().update 'counter_by_cardId'
    _.forEach diff, (amount, key) ->
      q = q.increment key, amount
    q.where 'cardId', '=', cardId
    .andWhere 'gameType', '=', gameType
    .andWhere 'arena', '=', arena
    .run()

  deckIdCardIdQueries = _.map deckIdCardIdCnt, (diff, key) ->
    [deckId, gameType, arena, cardId] = key.split ','
    diff = _.pickBy diff
    q = cknex().update 'counter_by_deckId_opponentCardId'
    _.forEach diff, (amount, key) ->
      q = q.increment key, amount
    q.where 'deckId', '=', deckId
    .andWhere 'gameType', '=', gameType
    .andWhere 'arena', '=', arena
    .andWhere 'opponentCardId', '=', cardId
    .run()

  Promise.all deckIdQueries.concat cardIdQueries, deckIdCardIdQueries

class ClashRoyaleMatchModel
  POSTGRES_TABLES: [
    {
      tableName: POSTGRES_MATCH_TABLE
      fields: fields
      indexes: []
    }
  ]

  batchCreate: (clashRoyaleMatches) ->
    Promise.all(
      runMatchesByPlayerId clashRoyaleMatches
      .concat runMatchesCounter clashRoyaleMatches
    )

    clashRoyaleMatches = _.map clashRoyaleMatches, defaultClashRoyaleMatch
    knex.insert(clashRoyaleMatches).into(POSTGRES_MATCH_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10

    q = knex POSTGRES_MATCH_TABLE
    .select '*'
    if userId
      q.where {userId}

    q.orderBy 'time', 'desc'
    .limit limit
    .map defaultClashRoyaleMatch

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
      .run {fetchSize: limit, pageState: cursorValue}
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
          rows: rows.map defaultClashRoyaleMatchC
          cursor: newCursor
        }

    # q = knex POSTGRES_MATCH_TABLE
    # .select '*'
    # .whereRaw '"teamPlayerIds" @> ARRAY[?]', [playerId]
    # # without this redundant orderby, postgres doesn't use the index
    # # https://stackoverflow.com/a/21386282
    # .orderBy 'teamPlayerIds', 'desc'
    # .orderBy 'time', 'desc'
    # .limit limit
    # .map defaultClashRoyaleMatch

  getById: (id, {preferCache} = {}) ->
    get = ->
      knex.table POSTGRES_MATCH_TABLE
      .first '*'
      .where {id}
      .then defaultClashRoyaleMatch

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID
      key = "#{prefix}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: SIX_HOURS_S}
    else
      get()


  # existsByPlayerIdAndTime: (playerId, time, {preferCache} = {}) ->
  #   console.log playerId, time
  #   get = ->
  #     cknex().where 'playerId', '=', playerId
  #     .andWhere 'time', '=', time
  #     .from 'matches_by_playerId'
  #     .run()
  #     .then (match) ->
  #       console.log 'existing', match
  #       Boolean match

  existsById: (id, {preferCache} = {}) ->
    get = ->
      knex.table POSTGRES_MATCH_TABLE
      .first 'id'
      .where {id}
      .then (match) ->
        Boolean match

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID_EXISTS
      key = "#{prefix}:#{id}"
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
