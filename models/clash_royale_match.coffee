_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'

knex = require '../services/knex'
CacheService = require '../services/cache'
config = require '../config'

POSTGRES_MATCH_TABLE = 'matches'
CLASH_ROYALE_MATCH_TABLE = 'clash_royale_matches'

ARENA_INDEX = 'arena'
TYPE_INDEX = 'type'
# TODO: migrate to PLAYER_IDS index
PLAYER_1_ID_INDEX = 'player1Id'
PLAYER_2_ID_INDEX = 'player2Id'
# PLAYER_1_USER_IDS_INDEX = 'player1UserIds'
# PLAYER_2_USER_IDS_INDEX = 'player2UserIds'
WINNING_DECK_ID_INDEX = 'winningDeckId'
LOSING_DECK_ID_INDEX = 'losingDeckId'
WINNING_CARD_IDS_INDEX = 'winningCardIds'
LOSING_CARD_IDS_INDEX = 'losingCardIds'
TIME_INDEX = 'time'
SIX_HOURS_S = 3600 * 6

defaultPlayer =
  deckId: null
  crowns: null
  playerName: null
  playerTag: null
  clanName: null
  clanTag: null
  trophies: null

fields = [
  {name: 'id', type: 'biginteger', index: 'primary'}
  {name: 'arena', type: 'integer', index: 'default'}
  {name: 'league', type: 'integer'}
  {name: 'player1Id', type: 'string', length: 20, index: 'default'}
  {name: 'player2Id', type: 'string', length: 20, index: 'default'}
  {name: 'winningDeckId', type: 'string', length: 150, index: 'default'}
  {name: 'losingDeckId', type: 'string', length: 150, index: 'default'}
  {
    name: 'type', type: 'string', length: 50, index: 'default'
    defaultValue: 'ladder'
  }
  {name: 'winningCardIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'losingCardIds', type: 'array', arrayType: 'text', index: 'gin'}
  {name: 'player1Data', type: 'json', defaultValue: defaultPlayer}
  {name: 'player2Data', type: 'json', defaultValue: defaultPlayer}
  {name: 'time', type: 'dateTime', index: 'default', defaultValue: new Date()}
]

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

class ClashRoyaleMatchModel
  POSTGRES_TABLES: [
    {
      tableName: POSTGRES_MATCH_TABLE
      fields: fields
      indexes: []
    }
  ]

  batchCreate: (clashRoyaleMatches) ->
    clashRoyaleMatches = _.map clashRoyaleMatches, defaultClashRoyaleMatch

    knex.insert(clashRoyaleMatches).into(POSTGRES_MATCH_TABLE)
    .catch (err) ->
      console.log 'postgres err', err


  create: (clashRoyaleMatch) ->
    clashRoyaleMatch = defaultClashRoyaleMatch clashRoyaleMatch

    knex.insert(clashRoyaleMatch).into(POSTGRES_MATCH_TABLE)
    .catch (err) ->
      console.log clashRoyaleMatch
      console.log 'postgres err', err

  getAllByUserId: ({limit, userId} = {}) ->
    limit ?= 10

    q = knex POSTGRES_MATCH_TABLE
    .select '*'
    if userId
      q.where {userId}

    q.orderBy 'time', 'desc'
    .limit limit
    .map defaultClashRoyaleMatch

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

  sanitize: _.curry (requesterId, clashRoyaleMatch) ->
    _.pick clashRoyaleMatch, [
      'id'
      'arena'
      'deck1Id'
      'deck2Id'
      'deck1Score'
      'deck2Score'
      'time'
    ]

module.exports = new ClashRoyaleMatchModel()
