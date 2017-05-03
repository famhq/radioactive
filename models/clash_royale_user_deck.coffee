_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
knex = require '../services/knex'
CacheService = require '../services/cache'
# TODO: rm
Deck = require './clash_royale_deck'
config = require '../config'

CLASH_ROYALE_USER_DECK_TABLE = 'clash_royale_user_decks'
POSTGRES_USER_DECKS_TABLE = 'user_decks'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'
DECK_ID_INDEX = 'deckId'
USER_ID_IS_FAVORITED_INDEX = 'userIdIsFavorited'
USER_ID_INDEX = 'userId'
DECK_ID_USER_ID_INDEX = 'deckIdUserId'
DECK_ID_PLAYER_ID_INDEX = 'deckIdPlayerId'
PLAYER_ID_INDEX = 'playerId'

ONE_HOUR_SECONDS = 3600

fields = [
  {name: 'id', type: 'uuid', index: 'primary', defaultValue: -> uuid.v4()}
  {name: 'name', type: 'string'}
  {name: 'deckId', type: 'string', length: 150}
  {name: 'wins', type: 'integer', defaultValue: 0}
  {name: 'losses', type: 'integer', defaultValue: 0}
  {name: 'draws', type: 'integer', defaultValue: 0}
  # indexed by userIdIsFavorited
  {name: 'userId', type: 'uuid'}
  {name: 'isFavorited', type: 'boolean', defaultValue: true}
  {name: 'playerId', type: 'string', length: 14, index: 'default'}
  {name: 'deckIdPlayerId', type: 'string', index: 'default'}
  {
    name: 'addTime', type: 'dateTime'
    defaultValue: new Date(), index: 'default'
  }
  {
    name: 'lastUpdateTime', type: 'dateTime', defaultValue: new Date()
    index: 'default'
  }
]

defaultClashRoyaleUserDeck = (clashRoyaleUserDeck) ->
  unless clashRoyaleUserDeck?
    return null

  clashRoyaleUserDeck?.deckIdPlayerId =
    "#{clashRoyaleUserDeck?.deckId}:#{clashRoyaleUserDeck?.playerId}"

  clashRoyaleUserDeck = _.pick clashRoyaleUserDeck, _.map(fields, 'name')

  _.defaults clashRoyaleUserDeck, _.reduce(fields, (obj, field) ->
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

class ClashRoyaleUserDeckModel
  POSTGRES_TABLES: [
    {
      tableName: POSTGRES_USER_DECKS_TABLE
      fields: fields
      indexes: [
        {columns: ['userId', 'isFavorited']}
        {columns: ['deckId', 'userId'], type: 'unique'}
      ]
    }
  ]
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_USER_DECK_TABLE
      options: {}
      indexes: [
        {name: LAST_UPDATE_TIME_INDEX}
        {
          name: USER_ID_IS_FAVORITED_INDEX
          fn: (row) ->
            [row('userId'), row('isFavorited')]
        }
        {
          name: DECK_ID_USER_ID_INDEX
          fn: (row) ->
            [row('deckId'), row('userId')]
        }
        {
          name: DECK_ID_PLAYER_ID_INDEX
          fn: (row) ->
            [row('deckId'), row('playerId')]
        }
        {name: USER_ID_INDEX}
        {name: DECK_ID_INDEX}
        {name: PLAYER_ID_INDEX}
      ]
    }
  ]


  batchCreate: (userDecks) ->
    userDecks = _.map userDecks, defaultClashRoyaleUserDeck

    Promise.all [
      knex(POSTGRES_USER_DECKS_TABLE).insert(userDecks)
      .catch (err) ->
        console.log 'postgres err', err

      # r.table CLASH_ROYALE_USER_DECK_TABLE
      # .insert userDecks, {durability: 'soft'}
      # .run()
    ]

  create: (clashRoyaleUserDeck) ->
    clashRoyaleUserDeck = defaultClashRoyaleUserDeck clashRoyaleUserDeck
    knex.insert(clashRoyaleUserDeck).into(POSTGRES_USER_DECKS_TABLE)
    .catch (err) ->
      console.log 'postgres', err
    .then ->
      clashRoyaleUserDeck

    # r.table CLASH_ROYALE_USER_DECK_TABLE
    # .insert clashRoyaleUserDeck, {durability: 'soft'}
    # .run()
    # .then ->
    #   clashRoyaleUserDeck

  # FIXME: remove after 5/5/2017
  importByUserId: (userId) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .group('deckId').ungroup()
    .map (userDeck) ->
      userDeck('reduction')(0)
    .run()
    .map defaultClashRoyaleUserDeck
    .then (userDecks) =>
      deckIds = _.map userDecks, ({deckId}) -> deckId?.split('|')
      Promise.map deckIds, Deck.getByCardKeys
      .then =>
        userDecks = _.map userDecks, (deck) ->
          delete deck.id
          deck
        @batchCreate userDecks

  getById: (id) ->
    if config.IS_POSTGRES or true
      knex POSTGRES_USER_DECKS_TABLE
      .first '*'
      .where {id}
      .then defaultClashRoyaleUserDeck
    else
      r.table CLASH_ROYALE_USER_DECK_TABLE
      .get id
      .run()
      .then defaultClashRoyaleUserDeck

  getByDeckIdAndUserId: (deckId, userId) ->
    if config.IS_POSTGRES or true
      knex POSTGRES_USER_DECKS_TABLE
      .first '*'
      .where {deckId, userId}
      .then defaultClashRoyaleUserDeck
    else
      r.table CLASH_ROYALE_USER_DECK_TABLE
      .getAll userId, {index: USER_ID_INDEX}
      .filter {deckId}
      .nth 0
      .default null
      .run()
      .then defaultClashRoyaleUserDeck

  getAllByPlayerId: (playerId, {preferCache} = {}) ->
    get = ->
      if config.IS_POSTGRES or true
        knex POSTGRES_USER_DECKS_TABLE
        .select '*'
        .where {playerId}
        .map defaultClashRoyaleUserDeck
      else
        r.table CLASH_ROYALE_USER_DECK_TABLE
        .getAll playerId, {index: PLAYER_ID_INDEX}
        .run()
        .map defaultClashRoyaleUserDeck

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_USER_DECK_PLAYER_ID
      key = "#{prefix}:#{playerId}"
      CacheService.preferCache key, get, {expireSeconds: ONE_HOUR_SECONDS}
    else
      get()

  getAllByDeckIdPlayerIds: (deckIdPlayerIds) ->
    if config.IS_POSTGRES or true
      knex POSTGRES_USER_DECKS_TABLE
      .select '*'
      .whereIn 'deckIdPlayerId', _.map deckIdPlayerIds, ({deckId, playerId}) ->
        "#{deckId}:#{playerId}"
      .map defaultClashRoyaleUserDeck
    else
      r.table CLASH_ROYALE_USER_DECK_TABLE
      .getAll r.args(deckIdPlayerIds), {index: DECK_ID_PLAYER_ID_INDEX}
      .run()
      .map defaultClashRoyaleUserDeck

  getAll: ({limit, sort, userId} = {}) ->
    limit ?= 10

    if config.IS_POSTGRES or true
      # TODO: index on wins?
      sortColumn = if sort is 'recent' then LAST_UPDATE_TIME_INDEX else 'wins'
      q = knex POSTGRES_USER_DECKS_TABLE
      .select '*'
      if userId
        q.where {userId}

      q.orderBy sortColumn, 'desc'
      .limit limit
      .map defaultClashRoyaleUserDeck

    else
      sortQ = if sort is 'recent' \
              then {index: r.desc(LAST_UPDATE_TIME_INDEX)}
              else if sort is 'popular'
              then r.desc(r.row('wins').add(r.row('losses')))
              else r.row('wins').add(r.row('losses'))

      r.table CLASH_ROYALE_USER_DECK_TABLE
      # if userId or true
      .getAll userId, {index: USER_ID_INDEX}
      .group('deckId').ungroup()
      .map (userDeck) ->
        userDeck('reduction')(0)
      .orderBy sortQ
      .limit limit
      .run()
      .map defaultClashRoyaleUserDeck

  getAllByUserId: (userId, {limit, sort} = {}) =>
    unless userId
      console.log 'user decks getall empty userid'
      return Promise.resolve null

    @getAll {limit, sort, userId}

  getAllFavoritedByUserId: (userId, {limit} = {}) ->
    limit ?= 10
    if config.IS_POSTGRES or true
      knex POSTGRES_USER_DECKS_TABLE
      .select '*'
      .where {userId, isFavorited: true}
      .limit limit
      .map defaultClashRoyaleUserDeck
    else
      r.table CLASH_ROYALE_USER_DECK_TABLE
      .getAll [userId, true], {index: USER_ID_IS_FAVORITED_INDEX}
      .limit limit
      .run()
      .map defaultClashRoyaleUserDeck

  processUpdate: (userId) ->
    key = CacheService.PREFIXES.USER_DATA_CLASH_ROYALE_DECK_IDS + ':' + userId
    CacheService.deleteByKey key

  # the fact that this actually works is a little peculiar. technically, it
  # should only increment a batched deck by max of 1, but getAll
  # for multiple of same id grabs the same id multiple times (and updates).
  # TODO: group by count, separate query to .add(count)
  # processIncrementByDeckIdAndPlayerId: ->
  #   states = ['win', 'loss', 'draw']
  #   _.map states, (state) ->
  #     subKey = "CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
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
  #       r.table CLASH_ROYALE_USER_DECK_TABLE
  #       .getAll r.args(queue), {index: DECK_ID_PLAYER_ID_INDEX}
  #       .update diff
  #       .run()


  # incrementByDeckIdAndPlayerId: (deckId, playerId, state, {batch} = {}) ->
  #   if batch
  #     subKey = "CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
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
  #     r.table CLASH_ROYALE_USER_DECK_TABLE
  #     .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
  #     .update diff, {durability: 'soft'}
  #     .run()

  incrementAllByDeckIdAndPlayerId: (deckId, playerId, changes) ->
    changes = _.mapValues changes, (increment, key) ->
      knex.raw "\"#{key}\" + #{increment}"
    knex POSTGRES_USER_DECKS_TABLE
    .where {deckIdPlayerId: "#{deckId}:#{playerId}"}
    .update _.defaults({lastUpdateTime: new Date()}, changes)
    .catch (err) ->
      console.log 'postgres err', err

    # diff = {
    #   wins: r.row('wins').add(changes.wins or 0)
    #   losses: r.row('losses').add(changes.losses or 0)
    #   draws: r.row('draws').add(changes.draws or 0)
    # }
    # r.table CLASH_ROYALE_USER_DECK_TABLE
    # .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
    # .update diff, {durability: 'soft'}
    # .run()

  # technically current deck is just the most recently used one...
  # resetCurrentByPlayerId: (playerId, diff) ->
  #   r.table CLASH_ROYALE_USER_DECK_TABLE
  #   .getAll playerId, {index: PLAYER_ID_INDEX}
  #   .filter {isCurrentDeck: true}
  #   .update {isCurrentDeck: false}
  #   .run()

  upsertByDeckIdAndUserId: (deckId, userId, diff) ->
    unless deckId and userId
      return Promise.resolve null
    # postgres
    Promise.all [
      upsert {
        table: POSTGRES_USER_DECKS_TABLE
        diff: defaultClashRoyaleUserDeck _.defaults _.clone(diff), {
          userId, deckId
        }
        constraint: '("deckId", "userId")'
      }

      # ideally upserts would use replace for atomicity, but replace doesn't work
      # with getAll atm
      # r.table CLASH_ROYALE_USER_DECK_TABLE
      # .getAll [deckId, userId], {index: DECK_ID_USER_ID_INDEX}
      # .nth 0
      # .default null
      # .do (userDeck) ->
      #   r.branch(
      #     userDeck.eq null
      #
      #     r.table CLASH_ROYALE_USER_DECK_TABLE
      #     .insert defaultClashRoyaleUserDeck _.defaults(_.clone(diff), {
      #       userId, deckId
      #     })
      #
      #     r.table CLASH_ROYALE_USER_DECK_TABLE
      #     .getAll [deckId, userId], {index: DECK_ID_USER_ID_INDEX}
      #     .nth 0
      #     .default null
      #     .update diff
      #   )
      # .run()
      # .then -> null
    ]

  # upsertByDeckIdAndPlayerId: (deckId, playerId, diff, {durability} = {}) ->
  #   durability ?= 'hard'
  #   r.table CLASH_ROYALE_USER_DECK_TABLE
  #   .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
  #   .nth 0
  #   .default null
  #   .do (userDeck) ->
  #     r.branch(
  #       userDeck.eq null
  #
  #       r.table CLASH_ROYALE_USER_DECK_TABLE
  #       .insert defaultClashRoyaleUserDeck(_.defaults(_.clone(diff), {
  #         playerId, deckId
  #       })), {durability}
  #
  #       r.table CLASH_ROYALE_USER_DECK_TABLE
  #       .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
  #       .nth 0
  #       .default null
  #       .update diff, {durability}
  #     )
  #   .run()
  #   .then -> null

  duplicateByPlayerId: (playerId, userId) ->
    # TODO: check perf of this
    knex POSTGRES_USER_DECKS_TABLE
    .select()
    .where {playerId}
    .distinct(knex.raw('ON ("deckId") *'))
    .map (userDeck) =>
      delete userDeck.id
      @create _.defaults {
        userId: userId
      }, userDeck
    #
    # r.table CLASH_ROYALE_USER_DECK_TABLE
    # .getAll playerId, {index: PLAYER_ID_INDEX}
    # .group 'deckId'
    # .run()
    # .map ({reduction}) =>
    #   userDeck = _.maxBy reduction, 'wins'
    #   @create _.defaults {
    #     id: uuid.v4()
    #     userId: userId
    #   }, userDeck

  deleteById: (id) ->
    knex POSTGRES_USER_DECKS_TABLE
    .where {id}
    .limit 1
    .del()

    # r.table CLASH_ROYALE_USER_DECK_TABLE
    # .get id
    # .delete()
    # .run()

  sanitize: _.curry (requesterId, clashRoyaleUserDeck) ->
    _.pick clashRoyaleUserDeck, [
      'id'
      'deckId'
      'deck'
      'name'
      'wins'
      'losses'
      'draws'
      'addTime'
      'isFavorited'
      'isCurrentDeck'
    ]

module.exports = new ClashRoyaleUserDeckModel()
