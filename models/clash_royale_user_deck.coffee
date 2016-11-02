_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

CLASH_ROYALE_USER_DECK_TABLE = 'clash_royale_user_decks'
ADD_TIME_INDEX = 'addTime'
DECK_ID_INDEX = 'deckId'
USER_ID_IS_FAVORITED_INDEX = 'userIdIsFavorited'
USER_ID_INDEX = 'userId'

defaultClashRoyaleDeck = (clashRoyaleUserDeck) ->
  unless clashRoyaleUserDeck?
    return null

  _.assign {
    id: uuid.v4()
    name: null
    isFavorited: true
    deckId: null
    wins: 0
    losses: 0
    draws: 0
    verifiedWins: 0
    verifiedLosses: 0
    verifiedDraws: 0
    addTime: new Date()
  }, clashRoyaleUserDeck

class ClashRoyaleUserDeckModel
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_USER_DECK_TABLE
      options: {}
      indexes: [
        {name: ADD_TIME_INDEX}
        {
          name: USER_ID_IS_FAVORITED_INDEX
          fn: (row) ->
            [row('userId'), row('isFavorited')]
        }
        {name: USER_ID_INDEX}
        {name: DECK_ID_INDEX}
      ]
    }
  ]

  create: (clashRoyaleUserDeck) ->
    clashRoyaleUserDeck = defaultClashRoyaleDeck clashRoyaleUserDeck

    r.table CLASH_ROYALE_USER_DECK_TABLE
    .insert clashRoyaleUserDeck
    .run()
    .then ->
      clashRoyaleUserDeck

  getById: (id) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .get id
    .run()
    .then defaultClashRoyaleDeck

  getAll: ({limit, sort} = {}) ->
    limit ?= 10

    sortQ = if sort is 'recent' \
            then {index: r.desc(ADD_TIME_INDEX)}
            else if sort is 'popular'
            then r.desc(r.row('wins').add(r.row('losses')))
            else r.row('wins').add(r.row('losses'))

    r.table CLASH_ROYALE_USER_DECK_TABLE
    .orderBy sortQ
    .limit limit
    .run()
    .map defaultClashRoyaleDeck

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .limit limit
    .run()
    .map defaultClashRoyaleDeck

  getAllFavoritedByUserId: (userId, {limit} = {}) ->
    limit ?= 10
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll [userId, true], {index: USER_ID_IS_FAVORITED_INDEX}
    .limit limit
    .run()
    .map defaultClashRoyaleDeck

  processUpdate: (userId) ->
    key = CacheService.PREFIXES.USER_DATA_CLASH_ROYALE_DECK_IDS + ':' + userId
    CacheService.deleteByKey key

  incrementByDeckIdAndUserId: (deckId, userId, state) ->
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
    .getAll userId, {index: USER_ID_INDEX}
    .filter {deckId}
    .update diff
    .run()

  upsertByDeckIdAndUserId: (deckId, userId, diff) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .filter {deckId}
    .nth 0
    .default null
    .do (userDeck) ->
      r.branch(
        userDeck.eq null

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .insert defaultClashRoyaleDeck _.defaults(diff, {userId, deckId})

        r.table CLASH_ROYALE_USER_DECK_TABLE
        .getAll userId, {index: USER_ID_INDEX}
        .filter {deckId}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then ->
      null


  deleteById: (id) ->
    r.table CLASH_ROYALE_USER_DECK_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, clashRoyaleUserDeck) ->
    _.pick clashRoyaleUserDeck, [
      'id'
      'deckId'
      'name'
      'wins'
      'losses'
      'draws'
      'addTime'
    ]

module.exports = new ClashRoyaleUserDeckModel()
