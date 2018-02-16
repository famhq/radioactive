_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

CLASH_ROYALE_CARD_TABLE = 'clash_royale_cards'
KEY_INDEX = 'key'
POPULARITY_INDEX = 'thisWeekPopularity'
ONE_WEEK_S = 3600 * 24 * 7
ONE_HOUR_S = 3600
TEN_MINUTES_SECONDS = 10 * 60

defaultClashRoyaleCard = (clashRoyaleCard) ->
  unless clashRoyaleCard?
    return null

  _.defaults clashRoyaleCard, {
    id: uuid.v4()
    name: null
    key: null
    wins: 0
    losses: 0
    draws: 0
  }

defaultClashRoyaleCardOutput = (clashRoyaleCard) ->
  unless clashRoyaleCard?
    return null

  _.defaults {
    arena: parseInt clashRoyaleCard.arena
    wins: parseInt clashRoyaleCard.wins
    losses: parseInt clashRoyaleCard.losses
    draws: parseInt clashRoyaleCard.draws
  }, clashRoyaleCard

class ClashRoyaleCardModel
  SCYLLA_TABLES: [
    {
      name: 'counter_by_cardId'
      keyspace: 'clash_royale'
      fields:
        cardId: 'text'
        gameType: 'text'
        arena: 'int'
        wins: 'counter'
        losses: 'counter'
        draws: 'counter'
      primaryKey:
        partitionKey: ['cardId']
        clusteringColumns: ['gameType', 'arena']
    }
  ]
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_CARD_TABLE
      options: {}
      indexes: [
        {name: KEY_INDEX}
        {name: POPULARITY_INDEX}
      ]
    }
  ]

  batchUpsertByMatches: (matches) ->
    cardIdCnt = {}

    # side effect cardIdCnt
    mapCardCondition = (condition, cardIds, gameType, arena) ->
      _.forEach cardIds, (cardId) ->
        key = [cardId, gameType, arena].join(',')
        allKey = [cardId, 'all', 0].join(',')
        cardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
        cardIdCnt[key][condition] += 1
        cardIdCnt[allKey] ?= {wins: 0, losses: 0, draws: 0}
        cardIdCnt[allKey][condition] += 1

    _.forEach matches, (match) ->
      gameType = match.type
      arena = if gameType is 'PvP' then match.arena else 0

      mapCardCondition 'wins', match.winningCardIds, gameType, arena
      mapCardCondition 'losses', match.losingCardIds, gameType, arena
      mapCardCondition 'draws', match.drawCardIds, gameType, arena

    cardIdQueries = _.map cardIdCnt, (diff, key) ->
      [cardId, gameType, arena] = key.split ','
      q = cknex('clash_royale').update 'counter_by_cardId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'cardId', '=', cardId
      .andWhere 'gameType', '=', gameType
      .andWhere 'arena', '=', arena

    cknex.batchRun cardIdQueries

  create: (clashRoyaleCard) ->
    clashRoyaleCard = defaultClashRoyaleCard clashRoyaleCard

    r.table CLASH_ROYALE_CARD_TABLE
    .insert clashRoyaleCard
    .run()
    .then ->
      clashRoyaleCard

  getById: (id) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .get id
    .run()
    .then defaultClashRoyaleCard
    .catch (err) ->
      console.log 'fail', id
      throw err

  getTop: ({gameType, preferCache} = {}) ->
    get = ->
      cknex('clash_royale').select '*'
      .from 'counter_by_cardId'
      .run()
      .then (allCards) ->
        cards = _.filter allCards, {gameType}
        cards = _.map cards, defaultClashRoyaleCardOutput
        cards = _.map cards, (card) ->
          _.defaults {
            winRate: card.wins / (card.wins + card.losses)
          }, card
        _.orderBy cards, 'winRate', 'desc'

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CARD_TOP
      cacheKey = "#{prefix}:#{gameType}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: TEN_MINUTES_SECONDS
      }
    else
      get()

  getPopularDecksByKey: (cardKey, {preferCache} = {}) ->
    get = ->
      prefix = CacheService.STATIC_PREFIXES.CARD_DECK_LEADERBOARD
      key = "#{prefix}:#{cardKey}"
      CacheService.leaderboardGet key, {limit: 5}
      .then (results) ->
        _.map _.chunk(results, 2), ([deckId, matchCount], i) ->
          {
            rank: i + 1
            deckId
            matchCount: parseInt matchCount
          }

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CARD_POPULAR_DECKS
      cacheKey = "#{prefix}:#{cardKey}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: TEN_MINUTES_SECONDS
      }
    else
      get()

  getStatsByKey: (key, {preferCache} = {}) ->
    get = ->
      cknex('clash_royale').select '*'
      .from 'counter_by_cardId'
      .where 'cardId', '=', key
      .run()
      .then (allCards) ->
        # cards = _.filter allCards, {arena: 'all'}
        cards = _.map allCards, defaultClashRoyaleCardOutput
        cards = _.map cards, (card) ->
          _.defaults {
            winRate: card.wins / (card.wins + card.losses)
          }, card
        _.orderBy cards, 'winRate', 'desc'

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CARD_STATS
      cacheKey = "#{prefix}:#{key}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: TEN_MINUTES_SECONDS
      }
    else
      get()

  getByKey: (key, {preferCache} = {}) ->
    unless key
      Promise.resolve null
    get = ->
      r.table CLASH_ROYALE_CARD_TABLE
      .getAll key, {index: KEY_INDEX}
      .nth 0
      .default null
      .run()
      .then defaultClashRoyaleCard

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CARD_KEY
      cacheKey = "#{prefix}:#{key}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_WEEK_S}
    else
      get()

  getAll: ({sort, preferCache} = {}) ->
    get = ->
      sortQ = if sort is 'popular' \
              then {index: r.desc(POPULARITY_INDEX)}
              else 'name'

      r.table CLASH_ROYALE_CARD_TABLE
      .orderBy sortQ
      .run()
      .map defaultClashRoyaleCard
      .then (cards) ->
        _.filter cards, ({key}) ->
          not (key in ['blank', 'golemite', 'lava_pup'])

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CARD_ALL
      cacheKey = "#{prefix}:#{sort}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_HOUR_S}
    else
      get()

  updateById: (id, diff) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .get id
    .update diff
    .run()

  updateByKey: (key, diff) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .getAll key, {index: KEY_INDEX}
    .nth 0
    .default null
    .update diff
    .run()

  deleteById: (id) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .get id
    .delete()
    .run()

  getKeyByName: (name) ->
    _.snakeCase name.replace /\./g, ''

  sanitize: _.curry (requesterId, clashRoyaleCard) ->
    _.pick clashRoyaleCard, [
      'id'
      'name'
      'key'
      'data'
      'stats'
      'popularDecks'
      'time'
    ]

  sanitizeLite: _.curry (requesterId, clashRoyaleCard) ->
    _.pick clashRoyaleCard, [
      'id'
      'name'
      'key'
    ]

module.exports = new ClashRoyaleCardModel()
