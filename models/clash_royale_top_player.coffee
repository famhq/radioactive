_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

CLASH_ROYALE_TOP_PLAYERS_TABLE = 'clash_royale_top_players'
RANK_INDEX = 'rank'

defaultClashRoyaleTopPlayer = (clashRoyaleTopPlayer) ->
  unless clashRoyaleTopPlayer?
    return null

  _.defaults clashRoyaleTopPlayer, {
    id: uuid.v4()
    rank: null
    playerId: null
  }

class ClashRoyaleTopPlayerModel
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_TOP_PLAYERS_TABLE
      options: {}
      indexes: [
        {name: RANK_INDEX}
      ]
    }
  ]

  create: (clashRoyaleTopPlayer) ->
    clashRoyaleTopPlayer = defaultClashRoyaleTopPlayer clashRoyaleTopPlayer

    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .insert clashRoyaleTopPlayer
    .run()
    .then ->
      clashRoyaleTopPlayer

  getById: (id) ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .get id
    .run()
    .then defaultClashRoyaleTopPlayer

  getAll: ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .orderBy r.desc('rank')
    .run()
    .map defaultClashRoyaleTopPlayer

  updateById: (id, diff) ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .get id
    .update diff
    .run()

  upsertByRank: (rank, diff) ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .getAll rank, {index: RANK_INDEX}
    .nth 0
    .default null
    .do (topPlayer) ->
      r.branch(
        topPlayer.eq null

        r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
        .insert defaultClashRoyaleTopPlayer _.defaults(_.clone(diff), {
          rank
        })

        r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
        .getAll rank, {index: RANK_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()

  updateByKey: (key, diff) ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .getAll key, {index: KEY_INDEX}
    .nth 0
    .default null
    .update diff
    .run()

  deleteById: (id) ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .get id
    .delete()
    .run()

  deleteAll: ->
    r.table CLASH_ROYALE_TOP_PLAYERS_TABLE
    .delete()
    .run()


module.exports = new ClashRoyaleTopPlayerModel()
