_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

knex = require '../services/knex'
CacheService = require '../services/cache'
config = require '../config'

PLAYER_DECKS_TABLE = 'player_decks'

ONE_HOUR_SECONDS = 3600

fields = [
  {name: 'id', type: 'uuid', index: 'primary', defaultValue: -> uuid.v4()}
  {name: 'deckId', type: 'string', length: 150}
  {name: 'playerId', type: 'string', length: 20}
  {name: 'deckIdPlayerIdType', type: 'string', length: 250, index: 'default'}
  {name: 'name', type: 'string'}
  {name: 'type', type: 'string', length: 100, defaultValue: 'all'}
  {name: 'wins', type: 'integer', defaultValue: 0}
  {name: 'losses', type: 'integer', defaultValue: 0}
  {name: 'draws', type: 'integer', defaultValue: 0}
  {
    name: 'addTime', type: 'dateTime'
    defaultValue: new Date(), index: 'default'
  }
  {
    name: 'lastUpdateTime', type: 'dateTime', defaultValue: new Date()
    index: 'default'
  }
]

defaultClashRoyalePlayerDeck = (clashRoyalePlayerDeck) ->
  unless clashRoyalePlayerDeck?
    return null

  clashRoyalePlayerDeck = _.pick clashRoyalePlayerDeck, _.map(fields, 'name')

  clashRoyalePlayerDeck?.deckIdPlayerIdType =
    "#{clashRoyalePlayerDeck?.deckId}:#{clashRoyalePlayerDeck?.playerId}" +
    ":#{clashRoyalePlayerDeck?.type}"

  _.defaults clashRoyalePlayerDeck, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if typeof defaultValue is 'function'
      obj[name] = defaultValue()
    else if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

upsert = ({table, diff, constraint}) ->
  insert = knex(table).insert(diff)
  update = knex.queryBuilder().update(diff)
  knex.raw "? ON CONFLICT #{constraint} DO ? returning *", [insert, update]
  .then (result) -> result.rows[0]

class ClashRoyalePlayerDeckModel
  POSTGRES_TABLES: [
    {
      tableName: PLAYER_DECKS_TABLE
      fields: fields
      indexes: [
        {columns: ['playerId', 'type', 'deckId'], type: 'unique'}
        {columns: ['playerId', 'lastUpdateTime']}
      ]
    }
  ]


  batchCreate: (playerDecks) ->
    playerDecks = _.map playerDecks, defaultClashRoyalePlayerDeck

    knex(PLAYER_DECKS_TABLE).insert(playerDecks)

  create: (clashRoyalePlayerDeck) ->
    clashRoyalePlayerDeck = defaultClashRoyalePlayerDeck clashRoyalePlayerDeck
    knex.insert(clashRoyalePlayerDeck).into(PLAYER_DECKS_TABLE)
    # .catch (err) ->
    #   console.log 'postgres', err
    .then ->
      clashRoyalePlayerDeck

  getById: (id) ->
    knex PLAYER_DECKS_TABLE
    .first '*'
    .where {id}
    .then defaultClashRoyalePlayerDeck

  getByDeckIdAndPlayerId: (deckId, playerId) ->
    knex PLAYER_DECKS_TABLE
    .first '*'
    .where {deckId, playerId}
    .then defaultClashRoyalePlayerDeck

  getAll: ({limit, sort, type, playerId} = {}) ->
    limit ?= 10

    # TODO: index on wins?
    sortColumn = if sort is 'recent' then 'lastUpdateTime' else 'wins'
    q = knex PLAYER_DECKS_TABLE
    .select '*'
    if playerId or type
      where = {}
      if playerId
        where.playerId = playerId
      if type
        where.type = type
      q.where where

    q.orderBy sortColumn, 'desc'
    .limit limit
    .map defaultClashRoyalePlayerDeck

  getAllByPlayerId: (playerId, {limit, sort, type} = {}) =>
    unless playerId
      console.log 'player decks getall empty playerId'
      return Promise.resolve null

    @getAll {limit, sort, type, playerId}

  processUpdate: (playerId) ->
    key = CacheService.PREFIXES.USER_DATA_CLASH_ROYALE_DECK_IDS + ':' + playerId
    CacheService.deleteByKey key

  # the fact that this actually works is a little peculiar. technically, it
  # should only increment a batched deck by max of 1, but getAll
  # for multiple of same id grabs the same id multiple times (and updates).
  # TODO: group by count, separate query to .add(count)
  # processIncrementByDeckIdAndPlayerId: ->
  #   states = ['win', 'loss', 'draw']
  #   _.map states, (state) ->
  #     subKey = "CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
  #     key = CacheService.KEYS[subKey]
  #     CacheService.arrayGet key
  #     .then (queue) ->
  #       CacheService.deleteByKey key
  #       console.log 'batch', queue.length
  #       if _.isEmpty queue
  #         return
  #
  #       queue = _.map queue, JSON.parse
  #       if state is 'win'
  #         diff = {
  #           wins: r.row('wins').add(1)
  #         }
  #       else if state is 'loss'
  #         diff = {
  #           losses: r.row('losses').add(1)
  #         }
  #       else if state is 'draw'
  #         diff = {
  #           draws: r.row('draws').add(1)
  #         }
  #       else
  #         diff = {}
  #
  #       diff.lastUpdateTime = new Date()
  #
  #       r.table CLASH_ROYALE_PLAYER_DECK_TABLE
  #       .getAll r.args(queue), {index: DECK_ID_PLAYER_ID_INDEX}
  #       .update diff
  #       .run()


  # incrementByDeckIdAndPlayerId: (deckId, playerId, state, {batch} = {}) ->
  #   if batch
  #     subKey = "CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
  #     key = CacheService.KEYS[subKey]
  #     CacheService.arrayAppend key, [deckId, playerId]
  #     Promise.resolve null # don't wait
  #   else
  #     if state is 'win'
  #       diff = {
  #         wins: r.row('wins').add(1)
  #       }
  #     else if state is 'loss'
  #       diff = {
  #         losses: r.row('losses').add(1)
  #       }
  #     else if state is 'draw'
  #       diff = {
  #         draws: r.row('draws').add(1)
  #       }
  #     else
  #       diff = {}
  #
  #     r.table CLASH_ROYALE_PLAYER_DECK_TABLE
  #     .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
  #     .update diff, {durability: 'soft'}
  #     .run()


  getAllByDeckIdAndPlayerIdAndTypes: (deckIdPlayerIdTypes) ->
    deckIdPlayerIdTypesStr = _.map deckIdPlayerIdTypes, (dpt) ->
      {deckId, playerId, type} = dpt
      "#{deckId}:#{playerId}:#{type}"

    # deckIdPlayerIdTypes = _.chunk deckIdPlayerIdTypes, 30

    knex PLAYER_DECKS_TABLE
    .select '*'
    .whereIn 'deckIdPlayerIdType', deckIdPlayerIdTypesStr
    .map defaultClashRoyalePlayerDeck


  incrementAllByDeckIdAndPlayerIdAndType: (deckId, playerId, type, changes) ->
    changes = _.mapValues changes, (increment, key) ->
      unless key in ['wins', 'losses', 'draws']
        throw new Error 'invalid key'
      if isNaN increment
        throw new Error 'invalid increment'
      knex.raw "\"#{key}\" + #{increment}"
    knex PLAYER_DECKS_TABLE
    .where {playerId, type, deckId}
    .update _.defaults({lastUpdateTime: new Date()}, changes)
    .catch (err) ->
      console.log 'postgres err', err

    # diff = {
    #   wins: r.row('wins').add(changes.wins or 0)
    #   losses: r.row('losses').add(changes.losses or 0)
    #   draws: r.row('draws').add(changes.draws or 0)
    # }
    # r.table CLASH_ROYALE_PLAYER_DECK_TABLE
    # .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
    # .update diff, {durability: 'soft'}
    # .run()

  # technically current deck is just the most recently used one...
  # resetCurrentByPlayerId: (playerId, diff) ->
  #   r.table CLASH_ROYALE_PLAYER_DECK_TABLE
  #   .getAll playerId, {index: PLAYER_ID_INDEX}
  #   .filter {isCurrentDeck: true}
  #   .update {isCurrentDeck: false}
  #   .run()

  upsertByDeckIdAndPlayerId: (deckId, playerId, diff) ->
    unless deckId and playerId
      return Promise.resolve null

    upsert {
      table: PLAYER_DECKS_TABLE
      diff: defaultClashRoyalePlayerDeck _.defaults _.clone(diff), {
        playerId, deckId
      }
      constraint: '("deckId", "playerId")'
    }

  migrateUserDecks: (playerId) ->
    knex 'user_decks'
    .select()
    .where {playerId}
    .distinct(knex.raw('ON ("deckId") *'))
    .map (userDeck) ->
      delete userDeck.id
      delete userDeck.isFavorited
      delete userDeck.deckIdPlayerId
      _.defaults {
        type: 'all'
      }, userDeck
    .then (playerDecks) =>
      @batchCreate playerDecks
      # .catch (err) ->
      #   console.log 'migrate deck err', err
    .catch -> null

  deleteById: (id) ->
    knex PLAYER_DECKS_TABLE
    .where {id}
    .limit 1
    .del()

    # r.table CLASH_ROYALE_PLAYER_DECK_TABLE
    # .get id
    # .delete()
    # .run()

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
