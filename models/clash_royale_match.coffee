_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'
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
  {name: 'player1Id', type: 'string', length: 14, index: 'default'}
  {name: 'player2Id', type: 'string', length: 14, index: 'default'}
  {name: 'winningDeckId', type: 'string', length: 150, index: 'default'}
  {name: 'losingDeckId', type: 'string', length: 150, index: 'default'}
  {
    name: 'type', type: 'string', length: 14, index: 'default'
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
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_MATCH_TABLE
      options: {}
      indexes: [
        {name: ARENA_INDEX}
        {name: PLAYER_1_ID_INDEX}
        {name: PLAYER_2_ID_INDEX}
        # {name: PLAYER_1_USER_IDS_INDEX, options: {multi: true}}
        # {name: PLAYER_2_USER_IDS_INDEX, options: {multi: true}}
        {name: TYPE_INDEX}
        {name: WINNING_DECK_ID_INDEX}
        {name: LOSING_DECK_ID_INDEX}
        {name: WINNING_CARD_IDS_INDEX, options: {multi: true}}
        {name: LOSING_CARD_IDS_INDEX, options: {multi: true}}
        {name: TIME_INDEX}
      ]
    }
  ]

  batchCreate: (clashRoyaleMatches) ->
    clashRoyaleMatches = _.map clashRoyaleMatches, defaultClashRoyaleMatch

    knex.insert(clashRoyaleMatches).into(POSTGRES_MATCH_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

    r.table CLASH_ROYALE_MATCH_TABLE
    .insert clashRoyaleMatches
    .run()

  create: (clashRoyaleMatch) ->
    clashRoyaleMatch = defaultClashRoyaleMatch clashRoyaleMatch

    knex.insert(clashRoyaleMatch).into(POSTGRES_MATCH_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

    r.table CLASH_ROYALE_MATCH_TABLE
    .insert clashRoyaleMatch
    .run()

  getById: (id, {preferCache} = {}) ->
    get = ->
      if config.IS_POSTGRES
        knex.table POSTGRES_MATCH_TABLE
        .first '*'
        .where {id}
        .then defaultClashRoyaleMatch
      else
        r.table CLASH_ROYALE_MATCH_TABLE
        .get id
        .run()
        .then defaultClashRoyaleMatch

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID
      key = "#{prefix}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  # getByTimeAndArena: (time, arena) ->
  #   r.table CLASH_ROYALE_MATCH_TABLE
  #   .getAll time, {index: TIME_INDEX}
  #   .filter {arena}
  #   .nth 0
  #   .default null
  #   .run()
  #   .then defaultClashRoyaleMatch

  # updateById: (id, diff) ->
  #   r.table CLASH_ROYALE_MATCH_TABLE
  #   .get id
  #   .update diff
  #   .run()
  #
  # deleteById: (id) ->
  #   r.table CLASH_ROYALE_MATCH_TABLE
  #   .get id
  #   .delete()
  #   .run()

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
