_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

CLASH_ROYALE_MATCH_TABLE = 'clash_royale_matches'

ARENA_INDEX = 'arena'
TYPE_INDEX = 'type'
PLAYER_1_ID_INDEX = 'player1Id'
PLAYER_2_ID_INDEX = 'player2Id'
# PLAYER_1_USER_IDS_INDEX = 'player1UserIds'
# PLAYER_2_USER_IDS_INDEX = 'player2UserIds'
WINNING_DECK_ID_INDEX = 'winningDeckId'
LOSING_DECK_ID_INDEX = 'losingDeckId'
WINNING_CARD_IDS_INDEX = 'winningCardIds'
LOSING_CARD_IDS_INDEX = 'losingCardIds'
TIME_INDEX = 'time'

defaultClashRoyaleMatch = (clashRoyaleMatch) ->
  unless clashRoyaleMatch?
    return null

  _.defaults clashRoyaleMatch, {
    id: uuid.v4()
    arena: null
    # player1UserIds: []
    # player2UserIds: []
    player1Id: null
    player2Id: null
    winningDeckId: null
    losingDeckId: null
    type: 'ladder'
    winningCardIds: []
    losingCardIds: []
    player1Data:
      deckId: null
      crowns: null
      playerName: null
      playerTag: null
      clanName: null
      clanTag: null
      trophies: null
    player2Data:
      deckId: null
      crowns: null
      playerName: null
      playerTag: null
      clanName: null
      clanTag: null
      trophies: null
    time: new Date()
  }

class ClashRoyaleMatchModel
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

  create: (clashRoyaleMatch) ->
    clashRoyaleMatch = defaultClashRoyaleMatch clashRoyaleMatch

    r.table CLASH_ROYALE_MATCH_TABLE
    .insert clashRoyaleMatch
    .run()

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table CLASH_ROYALE_MATCH_TABLE
      .get id
      .run()
      .then defaultClashRoyaleMatch

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID
      key = "#{prefix}:#{id}"
      CacheService.preferCache key, get
    else
      get()

  getAll: ({limit} = {}) ->
    limit ?= 10

    r.table CLASH_ROYALE_MATCH_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit limit
    .run()
    .map defaultClashRoyaleMatch

  getByTimeAndArena: (time, arena) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .getAll time, {index: TIME_INDEX}
    .filter {arena}
    .nth 0
    .default null
    .run()
    .then defaultClashRoyaleMatch

  updateById: (id, diff) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .get id
    .delete()
    .run()

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
