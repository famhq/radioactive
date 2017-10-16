_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

PLAYER_DECKS_TABLE = 'player_decks'

ONE_HOUR_SECONDS = 3600
ONE_MONTH_SECONDS = 3600 * 24 * 30

tables = [
  {
    name: 'counter_by_playerId_deckId'
    fields:
      playerId: 'text'
      deckId: 'text'
      gameType: 'text'
      wins: 'counter'
      losses: 'counter'
      draws: 'counter'
    primaryKey:
      partitionKey: ['playerId']
      clusteringColumns: ['gameType', 'deckId']
  }
  {
    # ttl 30 days so we only sort through decks used in last 30 days
    name: 'player_decks_by_playerId'
    fields:
      playerId: 'text'
      gameType: 'text'
      deckId: 'text'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['playerId']
      clusteringColumns: ['gameType', 'deckId']
  }
]

defaultClashRoyalePlayerDeck = (clashRoyalePlayerDeck) ->
  unless clashRoyalePlayerDeck?
    return null

  _.defaults {
    arena: parseInt clashRoyalePlayerDeck.arena
    wins: parseInt clashRoyalePlayerDeck.wins
    losses: parseInt clashRoyalePlayerDeck.losses
    draws: parseInt clashRoyalePlayerDeck.draws
  }, clashRoyalePlayerDeck

class ClashRoyalePlayerDeckModel
  SCYLLA_TABLES: tables

  batchUpsertByMatches: (matches) ->
    playerIdDeckIdCnt = {}
    now = new Date()

    mapDeckCondition = (condition, playerIds, deckIds, gameType) ->
      _.forEach playerIds, (playerId, i) ->
        deckId = deckIds[i]
        deckKey = [playerId, deckId, gameType].join(',')
        allDeckKey = [playerId, deckId, 'all'].join(',')
        playerIdDeckIdCnt[deckKey] ?= {wins: 0, losses: 0, draws: 0}
        playerIdDeckIdCnt[deckKey][condition] += 1
        playerIdDeckIdCnt[allDeckKey] ?= {wins: 0, losses: 0, draws: 0}
        playerIdDeckIdCnt[allDeckKey][condition] += 1

    _.forEach matches, (match) ->
      gameType = match.type
      if config.DECK_TRACKED_GAME_TYPES.indexOf(gameType) is -1
        return
      mapDeckCondition(
        'wins', match.winningPlayerIds, match.winningDeckIds, gameType
      )
      mapDeckCondition(
        'losses', match.losingPlayerIds, match.losingDeckIds, gameType
      )
      mapDeckCondition(
        'draws', match.drawPlayerIds, match.drawDeckIds, gameType
      )

    deckIdQueries = _.map playerIdDeckIdCnt, (diff, key) ->
      [playerId, deckId, gameType] = key.split ','
      cknex().update 'player_decks_by_playerId'
      .set {lastUpdateTime: now}
      .where 'playerId', '=', playerId
      .andWhere 'gameType', '=', gameType
      .andWhere 'deckId', '=', deckId
      .usingTTL ONE_MONTH_SECONDS

    countQueries = _.map playerIdDeckIdCnt, (diff, key) ->
      [playerId, deckId, gameType] = key.split ','
      q = cknex().update 'counter_by_playerId_deckId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'playerId', '=', playerId
      .andWhere 'gameType', '=', gameType
      .andWhere 'deckId', '=', deckId

    Promise.all [
      # batch is faster, but can't exceed 100mb
      cknex.batchRun deckIdQueries
      cknex.batchRun countQueries
    ]

  getByDeckIdAndPlayerId: (deckId, playerId) ->
    unless playerId and deckId
      return Promise.resolve null
    cknex().select '*'
    .where 'gameType', '=', 'all'
    .andWhere 'deckId', '=', deckId
    .andWhere 'playerId', '=', playerId
    .from 'counter_by_playerId_deckId'
    .run {isSingle: true}
    .then defaultClashRoyalePlayerDeck

  getAll: ({limit, type, playerId} = {}) ->
    type ?= 'all'
    limit ?= 10

    Promise.all [
      cknex().select '*'
      .where 'playerId', '=', playerId
      .andWhere 'gameType', '=', type
      .from 'player_decks_by_playerId'
      .run()

      q = cknex().select '*'
      .where 'playerId', '=', playerId
      .andWhere 'gameType', '=', type
      .from 'counter_by_playerId_deckId'
      .run()
    ]
    .then ([playerDecksWithTime, playerDecks]) ->
      selectedDecks = _.take(
        _.orderBy(playerDecksWithTime, 'lastUpdateTime', 'desc')
        limit
      )

      _.map selectedDecks, ({deckId}) ->
        _.find playerDecks, {deckId}
    .map defaultClashRoyalePlayerDeck

  getAllByPlayerId: (playerId, {limit, sort, type} = {}) =>
    unless playerId
      console.log 'player decks getall empty playerId'
      return Promise.resolve null

    @getAll {limit, sort, type, playerId}

  sanitize: _.curry (requesterId, clashRoyalePlayerDeck) ->
    _.pick clashRoyalePlayerDeck, [
      'id'
      'deckId'
      'deck'
      'name'
      'wins'
      'losses'
      'draws'
      'addTime'
    ]

module.exports = new ClashRoyalePlayerDeckModel()
