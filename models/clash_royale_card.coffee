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

class ClashRoyaleCardModel
  SCYLLA_TABLES: [
    {
      name: 'counter_by_cardId'
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
      mapCardCondition 'losses', match.winningCardIds, gameType, arena
      mapCardCondition 'draws', match.winningCardIds, gameType, arena

    cardIdQueries = _.map cardIdCnt, (diff, key) ->
      [cardId, gameType, arena] = key.split ','
      q = cknex().update 'counter_by_cardId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'cardId', '=', cardId
      .andWhere 'gameType', '=', gameType
      .andWhere 'arena', '=', arena
      .run()

    Promise.all cardIdQueries

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
      .filter r.row('key').ne('blank')
      .run()
      .map defaultClashRoyaleCard

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
      'cardIds'
      'data'
      'thisWeekPopularity'
      'timeRanges'
      'wins'
      'losses'
      'draws'
      'time'
    ]

module.exports = new ClashRoyaleCardModel()
