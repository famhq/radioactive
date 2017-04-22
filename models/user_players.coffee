_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

USER_PLAYERS_TABLE = 'user_players'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'

defaultUserPlayer = (userPlayer) ->
  unless userPlayer?
    return null

  _.defaults userPlayer, {
    id: uuid.v4()
    userId: null
    gameId: null
    playerId: null
  }

class UserPlayer
  RETHINK_TABLES: [
    {
      name: USER_PLAYERS_TABLE
      indexes: [
        {name: USER_ID_GAME_ID_INDEX}
        {name: PLAYER_ID_GAME_ID_INDEX}
      ]
    }
  ]

  create: (userPlayer) ->
    userPlayer = defaultUserPlayer userPlayer

    r.table USER_PLAYERS_TABLE
    .insert userPlayer
    .run()
    .then ->
      userPlayer

  getById: (id) ->
    r.table USER_PLAYERS_TABLE
    .get id
    .run()
    .then defaultUserPlayer

  updateById: (id, diff) ->
    r.table USER_PLAYERS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table USER_PLAYERS_TABLE
    .get id
    .delete()
    .run()

  getAllByUserId: (userId) ->
    r.table USER_PLAYERS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .filter {isActive: true}
    .run()
    .map defaultUserPlayer


module.exports = new UserPlayer()
