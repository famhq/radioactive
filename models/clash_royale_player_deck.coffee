_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

knex = require '../services/knex'
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
      .set {lastUpdateTime: new Date()}
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
      .andWhere 'deckId', '=', deckId
      .andWhere 'gameType', '=', gameType

    Promise.all [
      # batch is faster, but can't exceed 100mb
      cknex.batchRun deckIdQueries
      cknex.batchRun countQueries
    ]

  getByDeckIdAndPlayerId: (deckId, playerId) ->
    cknex().select '*'
    .where 'deckId', '=', deckId
    .andWhere 'playerId', '=', playerId
    .from 'counter_by_playerId_deckId'
    .run {isSingle: true}
    .then defaultClashRoyalePlayerDeck

  getAll: ({limit, type, playerId} = {}) ->
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
        _.orderBy(playerDecksWithTime, 'time', 'desc')
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

  migrate: (playerId) ->
    console.log 'migrate'
    knex 'player_decks'
    .select()
    .where {playerId}
    .map (playerDeck) ->
      delete playerDeck.id
      delete playerDeck.isFavorited
      delete playerDeck.deckIdPlayerId
      _.defaults {
        type: 'all'
      }, playerDeck
    .then (playerDecks) ->
      playerDecks = _.filter playerDecks, ({deckId}) ->
        deckId.indexOf('|') isnt -1
      chunks = cknex.chunkForBatch playerDecks
      Promise.all _.map chunks, (chunk) ->
        cknex.batchRun _.map chunk, ({playerId, deckId, type, lastUpdateTime} = {}) ->
          cknex().update 'player_decks_by_playerId'
          .set {lastUpdateTime}
          .where 'playerId', '=', playerId
          .andWhere 'gameType', '=', type
          .andWhere 'deckId', '=', deckId
          .usingTTL ONE_MONTH_SECONDS
        cknex.batchRun _.map chunk, ({playerId, deckId, type, wins, losses, draws} = {}) ->
          console.log playerId, deckId, type, wins, losses, draws
          cknex().update 'counter_by_playerId_deckId'
          .increment 'wins', wins
          .increment 'losses', losses
          .increment 'draws', draws
          .where 'playerId', '=', playerId
          .andWhere 'gameType', '=', type
          .andWhere 'deckId', '=', deckId
        cknex.batchRun _.map chunk, ({playerId, deckId, type, wins, losses, draws} = {}) ->
          console.log playerId, deckId, type, wins, losses, draws
          cknex().update 'counter_by_deckId'
          .increment 'wins', wins
          .increment 'losses', losses
          .increment 'draws', draws
          .andWhere 'gameType', '=', type
          .andWhere 'arena', '=', 0
          .andWhere 'deckId', '=', deckId
      # .catch (err) ->
      #   console.log 'migrate deck err', err
    .then ->
      console.log 'migrate done'
    .catch (err) ->
      console.log 'caught', err

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
