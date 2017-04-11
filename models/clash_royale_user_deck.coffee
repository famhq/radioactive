_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

CLASH_ROYALE_USER_DECK_TABLE = 'clash_royale_user_decks'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'
DECK_ID_INDEX = 'deckId'
USER_ID_IS_FAVORITED_INDEX = 'userIdIsFavorited'
USER_ID_INDEX = 'userId'
DECK_ID_USER_ID_INDEX = 'deckIdUserId'
DECK_ID_PLAYER_ID_INDEX = 'deckIdPlayerId'
PLAYER_ID_INDEX = 'playerId'

ONE_HOUR_SECONDS = 3600

defaultClashRoyaleUserDeck = (clashRoyaleUserDeck) ->
  unless clashRoyaleUserDeck?
    return null

  id = if clashRoyaleUserDeck?.userId and clashRoyaleUserDeck?.deckId \
       then "#{clashRoyaleUserDeck.userId}:#{clashRoyaleUserDeck.deckId}"
       else uuid.v4()

  _.defaults clashRoyaleUserDeck, {
    id: id
    isNewId: true

    name: null
    isFavorited: true
    deckId: null
    wins: 0
    losses: 0
    draws: 0
    userId: null
    playerId: null
    addTime: new Date()
    lastUpdateTime: new Date()
  }

class ClashRoyaleUserDeckModel
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

  create: (clashRoyaleUserDeck) ->
    clashRoyaleUserDeck = defaultClashRoyaleUserDeck clashRoyaleUserDeck
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .insert clashRoyaleUserDeck
    .run()
    .then ->
      clashRoyaleUserDeck

  getById: (id) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .get id
    .run()
    .then defaultClashRoyaleUserDeck

  getByDeckIdAndUserId: (deckId, userId) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .filter {deckId}
    .nth 0
    .default null
    .run()
    .then defaultClashRoyaleUserDeck

  getAllByPlayerId: (playerId, {preferCache} = {}) ->
    get = ->
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

  getAll: ({limit, sort} = {}) ->
    limit ?= 10

    sortQ = if sort is 'recent' \
            then {index: r.desc(LAST_UPDATE_TIME_INDEX)}
            else if sort is 'popular'
            then r.desc(r.row('wins').add(r.row('losses')))
            else r.row('wins').add(r.row('losses'))

    r.table CLASH_ROYALE_USER_DECK_TABLE
    .orderBy sortQ
    .limit limit
    .run()
    .map defaultClashRoyaleUserDeck

  getAllByUserId: (userId, {limit, sort} = {}) ->
    unless userId
      console.log 'user decks getall empty userid'
      return Promise.resolve null

    limit ?= 25

    sortQ = if sort is 'recent' \
            then r.desc(LAST_UPDATE_TIME_INDEX)
            else if sort is 'popular'
            then r.desc(r.row('wins').add(r.row('losses')))
            else r.desc(LAST_UPDATE_TIME_INDEX)

    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .orderBy sortQ
    .limit limit
    .run()
    .map defaultClashRoyaleUserDeck

  getAllFavoritedByUserId: (userId, {limit} = {}) ->
    limit ?= 10
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
  processIncrementByDeckIdAndPlayerId: ->
    states = ['win', 'loss', 'draw']
    _.map states, (state) ->
      subKey = "CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
      key = CacheService.KEYS[subKey]
      CacheService.arrayGet key
      .then (queue) ->
        CacheService.deleteByKey key
        console.log 'batch', queue.length
        if _.isEmpty queue
          return

        queue = _.map queue, JSON.parse
        if state is 'win'
          diff = {
            wins: r.row('wins').add(1)
          }
        else if state is 'loss'
          diff = {
            losses: r.row('losses').add(1)
          }
        else if state is 'draw'
          diff = {
            draws: r.row('draws').add(1)
          }
        else
          diff = {}

        diff.lastUpdateTime = new Date()

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .getAll r.args(queue), {index: DECK_ID_PLAYER_ID_INDEX}
        .update diff
        .run()


  incrementByDeckIdAndPlayerId: (deckId, playerId, state, {batch} = {}) ->
    if batch
      subKey = "CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
      key = CacheService.KEYS[subKey]
      CacheService.arrayAppend key, [deckId, playerId]
      Promise.resolve null # don't wait
    else
      if state is 'win'
        diff = {
          wins: r.row('wins').add(1)
        }
      else if state is 'loss'
        diff = {
          losses: r.row('losses').add(1)
        }
      else if state is 'draw'
        diff = {
          draws: r.row('draws').add(1)
        }
      else
        diff = {}

      r.table CLASH_ROYALE_USER_DECK_TABLE
      .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
      .update diff
      .run()

  # technically current deck is just the most recently used one...
  # resetCurrentByPlayerId: (playerId, diff) ->
  #   r.table CLASH_ROYALE_USER_DECK_TABLE
  #   .getAll playerId, {index: PLAYER_ID_INDEX}
  #   .filter {isCurrentDeck: true}
  #   .update {isCurrentDeck: false}
  #   .run()

  upsertByDeckIdAndUserId: (deckId, userId, diff) ->
    # ideally upserts would use replace for atomicity, but replace doesn't work
    # with getAll atm
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll [deckId, userId], {index: DECK_ID_USER_ID_INDEX}
    .nth 0
    .default null
    .do (userDeck) ->
      r.branch(
        userDeck.eq null

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .insert defaultClashRoyaleUserDeck _.defaults(_.clone(diff), {
          userId, deckId
        })

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .getAll [deckId, userId], {index: DECK_ID_USER_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then -> null

  upsertByDeckIdAndPlayerId: (deckId, playerId, diff, {durability} = {}) ->
    durability ?= 'hard'
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
    .nth 0
    .default null
    .do (userDeck) ->
      r.branch(
        userDeck.eq null

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .insert defaultClashRoyaleUserDeck(_.defaults(_.clone(diff), {
          playerId, deckId
        })), {durability}

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .getAll [deckId, playerId], {index: DECK_ID_PLAYER_ID_INDEX}
        .nth 0
        .default null
        .update diff, {durability}
      )
    .run()
    .then -> null

  duplicateByPlayerId: (playerId, userId) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll playerId, {index: PLAYER_ID_INDEX}
    .group 'deckId'
    .run()
    .map ({reduction}) =>
      userDeck = _.maxBy reduction, 'wins'
      @create _.defaults {
        id: uuid.v4()
        userId: userId
      }, userDeck

  deleteById: (id) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .get id
    .delete()
    .run()

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
