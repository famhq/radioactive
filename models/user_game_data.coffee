_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

STALE_INDEX = 'stale'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'
IS_QUEUED_INDEX = 'isQueued'

defaultUserGameData = (userGameData) ->
  unless userGameData?
    return null

  _.defaults userGameData, {
    id: uuid.v4()
    gameId: null
    playerId: null
    hasUserId: false
    userIds: [] # can be multiple users tied to a game user
    data:
      stats: {}
    isQueued: false
    lastUpdateTime: new Date()
  }

USER_GAME_DATA_TABLE = 'user_game_data'

class UserGameDataModel
  RETHINK_TABLES: [
    {
      name: USER_GAME_DATA_TABLE
      indexes: [
        {name: STALE_INDEX, fn: (row) ->
          [
            row('gameId')
            row('isQueued')
            row('hasUserId')
            row('lastUpdateTime')
          ]
        }
        {name: USER_ID_GAME_ID_INDEX
        options: {multi: true}, fn: (row) ->
          row('userIds').map (userId) ->
            [userId, row('gameId')]}
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

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (userGameData) ->
      r.branch(
        userGameData.eq null

        r.table USER_GAME_DATA_TABLE
        .insert defaultUserGameData _.defaults _.clone(diff), {
          playerId
          gameId
          hasUserId: Boolean userId
          userIds: if userId then [userId] else []
        }

        r.table USER_GAME_DATA_TABLE
        .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update _.defaults _.clone(diff), {
          # FIXME: figure out why this didn't work
          # hasUserId:
          #   r.expr(Boolean userId)
          #   .or(userGameData('userIds').count().gt(0))
          userIds: if userId \
                   then userGameData('userIds').append(userId).distinct()
                   else userGameData('userIds')
        }
      )
    .run()
    .then (a) ->
      null

  getStaleByGameId: (gameId, {staleTimeMs}) ->
    r.table USER_GAME_DATA_TABLE
    .between(
      [gameId, false, true, 0]
      [gameId, false, true, r.now().sub(staleTimeMs)]
      {index: STALE_INDEX}
    )
    .run()
    .map defaultUserGameData

  updateByPlayerIdsAndGameId: (playerIds, gameId, diff) ->
    playerIdGameIds = _.map playerIds, (playerId) ->
      [playerId, gameId]
    r.table USER_GAME_DATA_TABLE
    .getAll r.args(playerIdGameIds), {index: PLAYER_ID_GAME_ID_INDEX}
    .update diff
    .run()

  updateById: (id, diff) ->
    r.table USER_GAME_DATA_TABLE
    .get id
    .update diff
    .run()

module.exports = new UserGameDataModel()
