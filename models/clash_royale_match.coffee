_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'
config = require '../config'

CLASH_ROYALE_MATCH_TABLE = 'clash_royale_matches'
TIME_INDEX = 'time'

defaultClashRoyaleMatch = (clashRoyaleMatch) ->
  unless clashRoyaleMatch?
    return null

  _.assign {
    id: uuid.v4()
    arena: null
    deck1Id: null
    deck2Id: null
    deck1CardIds: null
    deck2CardIds: null
    deck1Score: null
    deck2Score: null
    time: new Date()
  }, clashRoyaleMatch

class ClashRoyaleMatchModel
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_MATCH_TABLE
      options: {}
      indexes: [
        {name: TIME_INDEX}
      ]
    }
  ]

  create: (clashRoyaleMatch) ->
    clashRoyaleMatch = defaultClashRoyaleMatch clashRoyaleMatch

    r.table CLASH_ROYALE_MATCH_TABLE
    .insert clashRoyaleMatch
    .run()
    .then ->
      clashRoyaleMatch

  getById: (id) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .get id
    .run()
    .then defaultClashRoyaleMatch

  getAll: ({limit} = {}) ->
    limit ?= 10

    r.table CLASH_ROYALE_MATCH_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit limit
    .run()
    .map defaultClashRoyaleMatch

  getByTimeAndArena: (time, arena) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .getAll time, {index: TIME_INDEX}
    .filter {arena}
    .nth 0
    .default null
    .run()
    .then defaultClashRoyaleMatch

  matchExists: ({arena, score1, score2, deck1Id, deck2Id, time}) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .between(
      moment(time).subtract(70, 'minutes').toDate()
      moment(time).add(70, 'minutes').toDate()
      {index: TIME_INDEX}
    )
    .filter {arena, deck1Id, deck2Id, deck1Score: score1, deck2Score: score2}
    .nth 0
    .default null
    .run()
    .then (match) ->
      Boolean match

  updateById: (id, diff) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table CLASH_ROYALE_MATCH_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, clashRoyaleMatch) ->
    _.pick clashRoyaleMatch, [
      'id'
      'arena'
      'deck1Id'
      'deck2Id'
      'deck1Score'
      'deck2Score'
      'time'
    ]

module.exports = new ClashRoyaleMatchModel()
