_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
UserPlayer = require './user_player'
ClashRoyalePlayer = require './clash_royale_player'
FortnitePlayer = require './fortnite_player'
User = require './user' # TODO rm
config = require '../config'

SIX_HOURS_S = 3600 * 6

class PlayerModel
  constructor: ->
    @GamePlayers =
      'clash-royale': ClashRoyalePlayer
      fortnite: FortnitePlayer


  batchUpsertByGameId: (gameKey, players) =>
    @GamePlayers[gameKey].batchUpsert players

  getByUserIdAndGameKey: (userId, gameKey, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_KEY
      cacheKey = "#{prefix}:#{userId}:#{gameKey}"
      CacheService.preferCache cacheKey, ->
        UserPlayer.getByUserIdAndGameKey userId, gameKey
      , {ignoreNull: true}
      .then (userPlayer) =>
        userPlayerExists = Boolean userPlayer?.playerId
        (if userPlayerExists
          @GamePlayers[gameKey].getById userPlayer?.playerId
        else
          Promise.resolve null
        )
        .then (player) ->
          if player
            _.defaults {isVerified: userPlayer.isVerified}, player

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_USER_ID_GAME_KEY
      cacheKey = "#{prefix}:#{userId}:#{gameKey}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getIsAutoRefreshByPlayerIdAndGameKey: (playerId, gameKey) =>
    @GamePlayers[gameKey].getIsAutoRefreshById playerId

  setAutoRefreshByPlayerIdAndGameKey: (playerId, gameKey) =>
    @GamePlayers[gameKey].setAutoRefreshById playerId

  getCountersByPlayerIdAndScaledTimeAndGameKey: (playerId, scaledTime, gameKey) =>
    @GamePlayers[gameKey].getCountersByPlayerIdAndScaledTime playerId, scaledTime

  getAutoRefreshByGameId: (gameKey, minReversedPlayerId) =>
    @GamePlayers[gameKey].getAutoRefresh minReversedPlayerId

  getAllByUserIdsAndGameKey: (userIds, gameKey) =>
    # maybe fixes crashing scylla? cache hits goes up to 500k
    userIds = _.take userIds, 100
    UserPlayer.getAllByUserIdsAndGameKey userIds, gameKey
    .then (players) =>
      playerIds = _.map players, 'playerId'
      @GamePlayers[gameKey].getAllByIds playerIds

  getByPlayerIdAndGameKey: (playerId, gameKey) =>
    unless @GamePlayers[gameKey]
      console.log 'gamekey not found', gameKey
      throw new Error 'gamekey not found'
    @GamePlayers[gameKey].getById playerId

  getAllByPlayerIdsAndGameKey: (playerIds, gameKey) =>
    # maybe fixes crashing scylla? cache hits goes up to 500k
    playerIds = _.take playerIds, 100
    @GamePlayers[gameKey].getAllByIds playerIds

  upsertByPlayerIdAndGameKey: (playerId, gameKey, diff, {userId} = {}) ->
    clonedDiff = _.cloneDeep(diff)

    (if userId and playerId
      UserPlayer.upsert {userId, gameKey, playerId}
      .then ->
        prefix = CacheService.PREFIXES.PLAYER_USER_IDS
        key = prefix + ':' + playerId
        CacheService.deleteByKey key
        prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_KEY
        cacheKey = "#{prefix}:#{userId}:#{gameKey}"
        CacheService.deleteByKey cacheKey
    else
      Promise.resolve null)
    .then =>
      @GamePlayers[gameKey].upsertById playerId, clonedDiff

  removeUserId: (userId, gameKey) ->
    unless userId
      console.log 'rm userId missing', userId
      return Promise.resolve null
    UserPlayer.deleteByUserIdAndGameKey userId, gameKey
    .tap ->
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_KEY
      cacheKey = "#{prefix}:#{userId}:#{gameKey}"
      CacheService.deleteByKey cacheKey

  deleteByPlayerIdAndGameKey: (playerId, gameKey) =>
    @GamePlayers[gameKey].deleteById playerId

module.exports = new PlayerModel()
