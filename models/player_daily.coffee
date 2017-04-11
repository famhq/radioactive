_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'

# TODO: create playersDailyRecords to store past days?

defaultPlayersDaily = (playersDaily) ->
  unless playersDaily?
    return null

  _.defaults playersDaily, {
    id: uuid.v4()
    gameId: null
    playerId: null
    data:
      stats: {}
    lastUpdateTime: new Date()
  }

PLAYER_DAILY_TABLE = 'players_daily'

class PlayersDailyModel
  RETHINK_TABLES: [
    {
      name: PLAYER_DAILY_TABLE
      indexes: [
        {name: PLAYER_ID_GAME_ID_INDEX, fn: (row) ->
          [row('playerId'), row('gameId')]}
      ]
    }
  ]

  batchCreate: (playersDaily) ->
    playersDaily = _.map playersDaily, defaultPlayersDaily

    r.table PLAYER_DAILY_TABLE
    .insert playersDaily
    .run()

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table PLAYER_DAILY_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultPlayersDaily
    .then (playersDaily) ->
      _.defaults {playerId}, playersDaily

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIdsGameIds = _.map playerIds, (playerId) -> [playerId, gameId]
    r.table PLAYER_DAILY_TABLE
    .getAll r.args(playerIdsGameIds), {index: PLAYER_ID_GAME_ID_INDEX}
    .map defaultPlayersDaily
    .run()

  updateByPlayerIdAndGameId: (playerId, gameId, diff) ->
    r.table PLAYER_DAILY_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .update diff
    .run()

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    r.table PLAYER_DAILY_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (playersDaily) ->
      r.branch(
        playersDaily.eq null

        r.table PLAYER_DAILY_TABLE
        .insert defaultPlayersDaily _.defaults _.clone(diff), {
          playerId
          gameId
          hasUserId: Boolean userId
          userIds: if userId then [userId] else []
        }

        r.table PLAYER_DAILY_TABLE
        .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  updateById: (id, diff) ->
    r.table PLAYER_DAILY_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table PLAYER_DAILY_TABLE
    .get id
    .delete()
    .run()

module.exports = new PlayersDailyModel()
