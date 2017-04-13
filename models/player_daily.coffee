_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'

# TODO: create playersDailyRecords to store past days?

defaultPlayersDaily = (playersDaily) ->
  unless playersDaily?
    return null

  id = if playersDaily?.playerId and playersDaily?.gameId \
       then "#{playersDaily.gameId}:#{playersDaily.playerId}"
       else uuid.v4()

  _.defaults playersDaily, {
    id: id
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
      indexes: []
    }
  ]

  batchCreate: (playersDaily) ->
    playersDaily = _.map playersDaily, defaultPlayersDaily

    r.table PLAYER_DAILY_TABLE
    .insert playersDaily
    .run()

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table PLAYER_DAILY_TABLE
    .getAll "#{gameId}:#{playerId}"
    .nth 0
    .default null
    .run()
    .then defaultPlayersDaily
    .then (playersDaily) ->
      _.defaults {playerId}, playersDaily

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIdsGameIds = _.map playerIds, (playerId) -> "#{gameId}:#{playerId}"
    r.table PLAYER_DAILY_TABLE
    .getAll r.args(playerIdsGameIds)
    .map defaultPlayersDaily
    .run()

  updateByPlayerIdAndGameId: (playerId, gameId, diff) ->
    r.table PLAYER_DAILY_TABLE
    .getAll "#{gameId}:#{playerId}"
    .update diff
    .run()

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    clonedDiff = _.cloneDeep(diff)

    r.table PLAYER_DAILY_TABLE
    .get "#{gameId}:#{playerId}"
    .replace (playerDaily) ->
      r.branch(
        playerDaily.eq null

        defaultPlayersDaily _.defaults _.clone(diff), {
          playerId
          gameId
          hasUserId: Boolean userId
          userIds: if userId then [userId] else []
        }

        playerDaily.merge _.defaults {
          hasUserId:
            r.expr(Boolean userId)
            .or(playerDaily('userIds').count().gt(0))
          userIds: if userId \
                   then playerDaily('userIds').append(userId).distinct()
                   else playerDaily('userIds')
        }, clonedDiff
      )
    .run()
    .then ->
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
