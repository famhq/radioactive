_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

USER_PLAYERS_TABLE = 'user_players'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'
PLAYER_ID_GAME_ID_IS_VERIFIED_INDEX = 'playerIdGameIdIsVerified'

defaultUserPlayer = (userPlayer) ->
  unless userPlayer?
    return null

  id = "#{userPlayer.gameId}:#{userPlayer.playerId}:#{userPlayer.userId}"

  _.defaults userPlayer, {
    id: id
    userId: null
    gameId: null
    playerId: null
    isVerified: false
  }

# scylla: user_players_by_userId, user_players_by_playerId

class UserPlayer
  RETHINK_TABLES: [
    {
      name: USER_PLAYERS_TABLE
      indexes: [
        {
          name: USER_ID_GAME_ID_INDEX
          fn: (row) -> [row('userId'), row('gameId')]
        }
        {
          name: PLAYER_ID_GAME_ID_INDEX
          fn: (row) -> [row('playerId'), row('gameId')]
        }
        {
          # not actually used
          name: PLAYER_ID_GAME_ID_IS_VERIFIED_INDEX
          fn: (row) -> [row('playerId'), row('gameId'), row('isVerified')]
        }
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

  deleteById: (id) ->
    r.table USER_PLAYERS_TABLE
    .get id
    .delete()
    .run()

  deleteByUserIdAndGameId: (userId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .delete()
    .run()

  getByUserIdAndGameId: (userId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserPlayer

  getVerifiedByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .filter {isVerified: true}
    .nth 0
    .default null
    .run()
    .then defaultUserPlayer

  setVerifiedByUserIdAndPlayerIdAndGameId: (userId, playerId, gameId) =>
    # mark others unverified
    @updateByPlayerIdAndGameId playerId, gameId, {
      isVerified: false
    }
    .then =>
      @updateByUserIdAndPlayerIdAndGameId(
        userId
        playerId
        gameId
        {isVerified: true}
      )
    .then ->
      key = CacheService.PREFIXES.PLAYER_VERIFIED_USER + ':' + playerId
      CacheService.deleteByKey key

  getByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserPlayer

  getAllByPlayerIdAndGameId: (playerId, gameId) ->
    r.table USER_PLAYERS_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .run()
    .map defaultUserPlayer

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIdsAndGameIds = _.map playerIds, (playerId) -> [playerId, gameId]
    r.table USER_PLAYERS_TABLE
    .getAll r.args(playerIdsAndGameIds), {index: PLAYER_ID_GAME_ID_INDEX}
    .run()
    .map defaultUserPlayer

  getAllByUserIdsAndGameId: (userIds, gameId) ->
    userIdsGameIds = _.map userIds, (userId) -> [userId, gameId]
    r.table USER_PLAYERS_TABLE
    .getAll r.args(userIdsGameIds), {index: USER_ID_GAME_ID_INDEX}
    .run()
    .map defaultUserPlayer

  upsertByUserIdAndGameId: (userId, gameId, diff) ->
    r.table USER_PLAYERS_TABLE
    .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (userPlayer) ->
      r.branch(
        userPlayer.eq null

        r.table USER_PLAYERS_TABLE
        .insert defaultUserPlayer _.defaults _.clone(diff), {userId, gameId}

        r.table USER_PLAYERS_TABLE
        .getAll [userId, gameId], {index: USER_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  updateByPlayerIdAndGameId: (playerId, gameId, diff) ->
    r.table USER_PLAYERS_TABLE
    .getAll [playerId, gameId], {index: PLAYER_ID_GAME_ID_INDEX}
    .update diff
    .run()

  updateByUserIdAndPlayerIdAndGameId: (userId, playerId, gameId, diff) ->
    prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_ID
    cacheKey = "#{prefix}:#{userId}:#{gameId}"

    r.table USER_PLAYERS_TABLE
    .get "#{gameId}:#{playerId}:#{userId}"
    .update diff
    .run()
    .tap ->
      CacheService.deleteByKey cacheKey
      null

  updateByPlayerIdsAndGameId: (playerIds, gameId, diff) ->
    playerIdGameIds = _.map playerIds, (playerId) -> [playerId, gameId]
    r.table USER_PLAYERS_TABLE
    .getAll r.expr(playerIds), {index: PLAYER_ID_GAME_ID_INDEX}
    .update diff
    .run()


module.exports = new UserPlayer()
