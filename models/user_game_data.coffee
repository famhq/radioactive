_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

GAME_ID_LAST_UPDATE_TIME_INDEX = 'gameIdLastUpdateTime'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'

defaultUserGameData = (userGameData) ->
  unless userGameData?
    return null

  _.defaults userGameData, {
    id: uuid.v4()
    gameId: null
    playerId: null
    userId: null
    data: {}
    lastUpdateTime: new Date()
  }

USER_GAME_DATA_TABLE = 'user_game_data'

class UserGameDataModel
  RETHINK_TABLES: [
    {
      name: USER_GAME_DATA_TABLE
      indexes: [
        {name: GAME_ID_LAST_UPDATE_TIME_INDEX, fn: (row) ->
          [row('gameId'), row('lastUpdateTime')]}
        {name: USER_ID_GAME_ID_INDEX, fn: (row) ->
          [row('userId'), row('gameId')]}
        {name: PLAYER_ID_GAME_ID_INDEX, fn: (row) ->
          [row('playerId'), row('gameId')]}
      ]
    }
  ]

  getByUserIdAndGameId: (userId, gameId) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGameData
    .then (userGameData) ->
      _.defaults {userId}, userGameData

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGameData
    .then (userGameData) ->
      _.defaults {playerId}, userGameData

  upsertByUserIdAndGameId: (userId, gameId, diff) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (userGameData) ->
      r.branch(
        userGameData.eq null

        r.table USER_GAME_DATA_TABLE
        .insert defaultUserGameData _.defaults _.clone(diff), {userId, gameId}

        r.table USER_GAME_DATA_TABLE
        .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  getStale: ({gameId, staleTimeMs}) ->
    r.table USER_GAME_DATA_TABLE
    .between(
      [gameId, 0]
      [gameId, r.now().sub(staleTimeMs)]
      {index: GAME_ID_LAST_UPDATE_TIME_INDEX}
    )

  updateById: (id, diff) ->
    r.table USER_GAME_DATA_TABLE
    .get id
    .update diff
    .run()

module.exports = new UserGameDataModel()
