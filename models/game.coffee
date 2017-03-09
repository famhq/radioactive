_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

KEY_INDEX = 'key'

defaultGame = (game) ->
  unless game?
    return null

  _.defaults game, {
    id: uuid.v4()
    key: null
  }

GAMES_TABLE = 'games'

class GameModel
  RETHINK_TABLES: [
    {
      name: GAMES_TABLE
      indexes: [{name: KEY_INDEX}]
    }
  ]

  create: (game) ->
    game = defaultGame game

    r.table GAMES_TABLE
    .insert game
    .run()
    .then ->
      game

  getByKey: (key) ->
    r.table GAMES_TABLE
    .getAll key, {index: KEY_INDEX}
    .nth 0
    .default null
    .run()

  updateById: (id, diff) ->
    r.table GAMES_TABLE
    .get id
    .update diff
    .run()

module.exports = new GameModel()
