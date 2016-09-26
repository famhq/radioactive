_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

CLASH_ROYALE_CARD_TABLE = 'clash_royale_cards'
KEY_INDEX = 'key'

defaultClashRoyaleCard = (clashRoyaleCard) ->
  unless clashRoyaleCard?
    return null

  _.assign {
    id: uuid.v4()
    name: null
    key: null
    wins: 0
    losses: 0
    draws: 0
    verifiedWins: 0
    verifiedLosses: 0
    verifiedDraws: 0
  }, clashRoyaleCard

class ClashRoyaleCardModel
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_CARD_TABLE
      options: {}
      indexes: [
        {name: KEY_INDEX}
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

  getByKey: (key) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .getAll key, {index: KEY_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultClashRoyaleCard

  getAll: ({sort}) ->
    sortQ = if sort is 'popular' \
            then r.desc(r.row('wins').add(r.row('losses')))
            else 'name'

    r.table CLASH_ROYALE_CARD_TABLE
    .orderBy sortQ
    .run()
    .map defaultClashRoyaleCard

  getRank: (deck) ->
    r.table CLASH_ROYALE_CARD_TABLE
    .filter(
      r.row('wins').add(r.row('losses'))
      .gt(deck.wins + deck.losses)
    )
    .count()
    .run()
    .then (rank) -> rank + 1

  incrementById: (id, state) ->
    if state is 'win'
      diff = {
        wins: r.row('wins').add(1)
        verifiedWins: r.row('verifiedWins').add(1)
      }
    else if state is 'loss'
      diff = {
        losses: r.row('losses').add(1)
        verifiedLosses: r.row('verifiedLosses').add(1)
      }
    else if state is 'draw'
      diff = {
        draws: r.row('draws').add(1)
        verifiedDraws: r.row('verifiedDraws').add(1)
      }
    else
      diff = {}

    r.table CLASH_ROYALE_CARD_TABLE
    .get id
    .update diff
    .run()

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
      'popularity'
      'wins'
      'losses'
      'draws'
      'time'
    ]

module.exports = new ClashRoyaleCardModel()
