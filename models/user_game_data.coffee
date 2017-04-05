_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

STALE_PLAYER_MATCHES_INDEX = 'stalePlayerMatches'
STALE_PLAYER_DATA_INDEX = 'stale'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'
IS_QUEUED_INDEX = 'isQueued'

# 500 ids per min = 30,000 per hour
# FIXME FIXME: bump up. see why so many writes happen per small user updates
DEFAULT_PLAYER_MATCHES_STALE_LIMIT = 500
# 40 players per minute = ~60,000 per day
DEFAULT_PLAYER_DATA_STALE_LIMIT = 80

defaultUserGameData = (userGameData) ->
  unless userGameData?
    return null

  _.defaults userGameData, {
    id: uuid.v4()
    gameId: null
    playerId: null
    hasUserId: false
    verifiedUserId: null
    isClaimed: false
    userIds: [] # can be multiple users tied to a game user
    data:
      stats: {}
    isQueued: false
    lastUpdateTime: new Date() # playerData
    lastMatchesUpdateTime: new Date()
  }

USER_GAME_DATA_TABLE = 'user_game_data'

class UserGameDataModel
  RETHINK_TABLES: [
    {
      name: USER_GAME_DATA_TABLE
      indexes: [
        {name: STALE_PLAYER_MATCHES_INDEX, fn: (row) ->
          [
            row('gameId')
            row('isQueued')
            row('hasUserId')
            row('lastMatchesUpdateTime')
          ]
        }
        {name: STALE_PLAYER_DATA_INDEX, fn: (row) ->
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

  create: (userGameData) ->
    userGameData = defaultUserGameData userGameData

    r.table USER_GAME_DATA_TABLE
    .insert userGameData
    .run()
    .then ->
      userGameData

  batchCreate: (userGameData) ->
    userGameData = _.map userGameData, defaultUserGameData

    r.table USER_GAME_DATA_TABLE
    .insert userGameData
    .run()

  getByUserIdAndGameId: (userId, gameId) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGameData
    .then (userGameData) ->
      _.defaults {userId}, userGameData

  updateByPlayerIdAndGameId: (playerId, gameId, diff) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .update diff
    .run()

  getAllByUserIdsAndGameId: (userIds, gameId) ->
    userIdsGameIds = _.map userIds, (userId) -> [userId, gameId]
    r.table USER_GAME_DATA_TABLE
    .getAll r.args(userIdsGameIds), {index: USER_ID_GAME_ID_INDEX}
    .map defaultUserGameData
    .run()

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_GAME_DATA_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGameData
    .then (userGameData) ->
      if userGameData
        _.defaults {playerId}, userGameData
      else null

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIdsGameIds = _.map playerIds, (playerId) -> [playerId, gameId]
    r.table USER_GAME_DATA_TABLE
    .getAll r.args(playerIdsGameIds), {index: PLAYER_ID_GAME_ID_INDEX}
    .map defaultUserGameData
    .run()

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    clonedDiff = _.cloneDeep(diff)

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
        .update _.defaults {
          hasUserId:
            r.expr(Boolean userId)
            .or(userGameData('userIds').count().gt(0))
          userIds: if userId \
                   then userGameData('userIds').append(userId).distinct()
                   else userGameData('userIds')
        }, clonedDiff
      )
    .run()
    .then ->
      null

  getStaleByGameId: (gameId, {staleTimeS, type, limit}) ->
    if type is 'matches'
      index = STALE_PLAYER_MATCHES_INDEX
      limit ?= DEFAULT_PLAYER_MATCHES_STALE_LIMIT
    else
      index = STALE_PLAYER_DATA_INDEX
      limit ?= DEFAULT_PLAYER_DATA_STALE_LIMIT
    r.table USER_GAME_DATA_TABLE
    .between(
      [gameId, false, true, 0]
      [gameId, false, true, r.now().sub(staleTimeS)]
      {index}
    )
    .limit limit
    .run()
    .map defaultUserGameData

  removeUserId: (userId, gameId) ->
    unless userId
      console.log 'rm userId missing', userId
      return Promise.resolve null
    r.table USER_GAME_DATA_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .update {
      userIds: r.row('userIds').setDifference([userId])
    }
    .run()

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
