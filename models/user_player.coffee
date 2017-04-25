_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

USER_PLAYERS_TABLE = 'user_players'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'
PLAYER_ID_GAME_ID_IS_VERIFIED_INDEX = 'playerIdGameIdIsVerified'

defaultUserPlayer = (userPlayer) ->
  unless userPlayer?
    return null

  _.defaults userPlayer, {
    id: uuid.v4()
    userId: null
    gameId: null
    playerId: null
    isVerified: false
  }

class UserPlayer
  RETHINK_TABLES: [
    {
      name: USER_PLAYERS_TABLE
      indexes: [
        {name: USER_ID_GAME_ID_INDEX}
        {name: PLAYER_ID_GAME_ID_INDEX}
        {name: PLAYER_ID_GAME_ID_IS_VERIFIED_INDEX}
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

  getByUserIdAndGameId: (userId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserPlayer

  getAllByUserIdsAndGameId: (userIds, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll r.args(userIdsGameIds), {index: USER_ID_GAME_ID_INDEX}
    .run()
    .map defaultUserPlayer

module.exports = new UserPlayer()
