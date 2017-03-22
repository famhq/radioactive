_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'

# TODO: create userGameDailyDataRecords to store past days?

defaultUserGameDailyData = (userGameDailyData) ->
  unless userGameDailyData?
    return null

  _.defaults userGameDailyData, {
    id: uuid.v4()
    gameId: null
    playerId: null
    data:
      stats: {}
    lastUpdateTime: new Date()
  }

USER_GAME_DATA_DAILY_TABLE = 'user_game_daily_data'

class UserGameDailyDataModel
  RETHINK_TABLES: [
    {
      name: USER_GAME_DATA_DAILY_TABLE
      indexes: [
        {name: PLAYER_ID_GAME_ID_INDEX, fn: (row) ->
          [row('playerId'), row('gameId')]}
      ]
    }
  ]

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_GAME_DATA_DAILY_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGameDailyData
    .then (userGameDailyData) ->
      _.defaults {playerId}, userGameDailyData

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    r.table USER_GAME_DATA_DAILY_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (userGameDailyData) ->
      r.branch(
        userGameDailyData.eq null

        r.table USER_GAME_DATA_DAILY_TABLE
        .insert defaultUserGameDailyData _.defaults _.clone(diff), {
          playerId
          gameId
          hasUserId: Boolean userId
          userIds: if userId then [userId] else []
        }

        r.table USER_GAME_DATA_DAILY_TABLE
        .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  updateById: (id, diff) ->
    r.table USER_GAME_DATA_DAILY_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table USER_GAME_DATA_DAILY_TABLE
    .get id
    .delete()
    .run()

module.exports = new UserGameDailyDataModel()
