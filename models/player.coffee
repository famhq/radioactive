_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

STALE_PLAYER_MATCHES_INDEX = 'stalePlayerMatches'
STALE_PLAYER_DATA_INDEX = 'stale'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
IS_QUEUED_INDEX = 'isQueued'

# 600 ids per min = 36,000 per hour
# FIXME FIXME: bump up. see why so many writes happen per small user updates
DEFAULT_PLAYER_MATCHES_STALE_LIMIT = 10 # 1500
# 40 players per minute = ~60,000 per day
DEFAULT_PLAYER_DATA_STALE_LIMIT = 1 # FIXME 100
SIX_HOURS_S = 3600 * 6

defaultPlayer = (player) ->
  unless player?
    return null

  id = if player?.playerId and player?.gameId \
       then "#{player.gameId}:#{player.playerId}"
       else uuid.v4()

  _.defaults player, {
    id: id
    gameId: null
    playerId: null
    hasUserId: false # alias for isTrackedUser
    verifiedUserId: null
    isClaimed: false
    userIds: [] # can be multiple users tied to a game user
    data:
      stats: {}
    isQueued: false
    lastUpdateTime: new Date() # playerData
    lastMatchesUpdateTime: new Date()
    lastQueuedTime: null
  }

PLAYER_TABLE = 'players'

class PlayerModel
  RETHINK_TABLES: [
    {
      name: PLAYER_TABLE
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
      ]
    }
  ]

  batchCreate: (player) ->
    player = _.map player, defaultPlayer

    r.table PLAYER_TABLE
    .insert player
    .run()

  getByUserIdAndGameId: (userId, gameId, {preferCache} = {}) ->
    get = ->
      r.table PLAYER_TABLE
      .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
      .nth 0
      .default null
      .run()
      .then defaultPlayer
      .then (player) ->
        _.defaults {userId}, player

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  updateByPlayerIdAndGameId: (playerId, gameId, diff) ->
    r.table PLAYER_TABLE
    .get "#{gameId}:#{playerId}"
    .update diff
    .run()

  getAllByUserIdsAndGameId: (userIds, gameId) ->
    userIdsGameIds = _.map userIds, (userId) -> [userId, gameId]
    r.table PLAYER_TABLE
    .getAll r.args(userIdsGameIds), {index: USER_ID_GAME_ID_INDEX}
    .map defaultPlayer
    .run()

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table PLAYER_TABLE
    .get "#{gameId}:#{playerId}"
    .run()
    .then defaultPlayer
    .then (player) ->
      if player
        _.defaults {playerId}, player
      else null

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIdsGameIds = _.map playerIds, (playerId) -> "#{gameId}:#{playerId}"
    r.table PLAYER_TABLE
    .getAll r.args(playerIdsGameIds)
    .map defaultPlayer
    .run()

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    clonedDiff = _.cloneDeep(diff)

    r.table PLAYER_TABLE
    .get "#{gameId}:#{playerId}"
    .replace (player) ->
      r.branch(
        player.eq null

        defaultPlayer _.defaults _.clone(diff), {
          playerId
          gameId
          hasUserId: Boolean userId
          userIds: if userId then [userId] else []
        }

        player.merge _.defaults {
          hasUserId:
            r.expr(Boolean userId)
            .or(player('userIds').count().gt(0))
          userIds: if userId \
                   then player('userIds').append(userId).distinct()
                   else player('userIds')
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
    r.table PLAYER_TABLE
    .between(
      [gameId, false, true, 0]
      [gameId, false, true, r.now().sub(staleTimeS)]
      {index}
    )
    .limit limit
    .run()
    .map defaultPlayer

  removeUserId: (userId, gameId) ->
    unless userId
      console.log 'rm userId missing', userId
      return Promise.resolve null
    r.table PLAYER_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .update {
      userIds: r.row('userIds').setDifference([userId])
    }
    .run()

  updateByPlayerIdsAndGameId: (playerIds, gameId, diff) ->
    playerIdGameIds = _.map playerIds, (playerId) -> "#{gameId}:#{playerId}"
    r.table PLAYER_TABLE
    .getAll r.args(playerIdGameIds)
    .update diff
    .run()

  updateById: (id, diff) ->
    r.table PLAYER_TABLE
    .get id
    .update diff
    .run()

module.exports = new PlayerModel()
