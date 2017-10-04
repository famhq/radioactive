_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
UserPlayer = require './user_player'
ClashRoyalePlayer = require './clash_royale_player'
User = require './user' # TODO rm
config = require '../config'

SIX_HOURS_S = 3600 * 6

class PlayerModel
  constructor: ->
    @GamePlayers =
      "#{config.CLASH_ROYALE_ID}": ClashRoyalePlayer

  batchUpsertByGameId: (gameId, players) =>
    @GamePlayers[gameId].batchUpsert players

  getByUserIdAndGameId: (userId, gameId, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, ->
        UserPlayer.getByUserIdAndGameId userId, gameId
      , {ignoreNull: true}
      .then (userPlayer) =>
        userPlayerExists = Boolean userPlayer?.playerId
        (if userPlayerExists
          @GamePlayers[gameId].getById userPlayer?.playerId
        else
          Promise.resolve null
        )
        .then (player) ->
          if player
            _.defaults {isVerified: userPlayer.isVerified}, player

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  setAutoRefreshByPlayerIdAndGameId: (playerId, gameId) =>
    @GamePlayers[gameId].setAutoRefreshById playerId

  getCountersByPlayerIdAndScaledTimeAndGameId: (playerId, scaledTime, gameId) =>
    @GamePlayers[gameId].getCountersByPlayerIdAndScaledTime playerId, scaledTime

  getAutoRefreshByGameId: (gameId, minReversedPlayerId) =>
    @GamePlayers[gameId].getAutoRefresh minReversedPlayerId

  getAllByUserIdsAndGameId: (userIds, gameId) =>
    UserPlayer.getAllByUserIdsAndGameId userIds, gameId
    .then (players) =>
      playerIds = _.map players, 'playerId'
      @GamePlayers[gameId].getAllByIds playerIds

  getByPlayerIdAndGameId: (playerId, gameId) =>
    @GamePlayers[gameId].getById playerId

  getAllByPlayerIdsAndGameId: (playerIds, gameId) =>
    @GamePlayers[gameId].getAllByIds playerIds

  upsertByPlayerIdAndGameId: (playerId, gameId, diff, {userId} = {}) ->
    clonedDiff = _.cloneDeep(diff)

    (if userId
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, ->
        UserPlayer.create {userId, gameId, playerId}
      , {ignoreNull: true}
      .then ->
        prefix = CacheService.PREFIXES.PLAYER_USER_IDS
        key = prefix + ':' + playerId
        CacheService.deleteByKey key
    else
      Promise.resolve null)
    .then =>
      @GamePlayers[gameId].upsertById playerId, clonedDiff

  removeUserId: (userId, gameId) ->
    unless userId
      console.log 'rm userId missing', userId
      return Promise.resolve null
    UserPlayer.deleteByUserIdAndGameId userId, gameId
    .tap ->
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.deleteByKey cacheKey

  deleteByPlayerIdAndGameId: (playerId, gameId) =>
    @GamePlayers[gameId].deleteById playerId

module.exports = PlayerModel
