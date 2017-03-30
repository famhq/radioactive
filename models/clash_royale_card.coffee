_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

ClashRoyaleWinTrackerModel = require './clash_royale_win_tracker'
r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

CLASH_ROYALE_CARD_TABLE = 'clash_royale_cards'
KEY_INDEX = 'key'
POPULARITY_INDEX = 'thisWeekPopularity'
ONE_DAY = 3600 * 24

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

class ClashRoyaleCardModel extends ClashRoyaleWinTrackerModel
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
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_DAY}
    else
      get()

  getAll: ({sort} = {}) ->
    sortQ = if sort is 'popular' \
            then {index: r.desc(POPULARITY_INDEX)}
            else 'name'

    r.table CLASH_ROYALE_CARD_TABLE
    .orderBy sortQ
    .filter r.row('key').ne('blank')
    .run()
    .map defaultClashRoyaleCard

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
