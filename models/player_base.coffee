_ = require 'lodash'

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

  batchCreateByGameId: (gameId, players) =>
    @GamePlayers[gameId].batchCreate players

  # TODO: remove after ~June 2017?
  migrate: ({userId, gameId, userPlayerExists}) =>
    User.getById userId
    .then (user) =>
      if (new Date(user?.joinTime).getTime()) < 1494354950636
        r.db('radioactive').table('players')
        .getAll [userId, gameId], {index: 'userIdGameId'}
        .nth 0
        .default null
        .run()
        .then (oldPlayer) =>
          if oldPlayer?.playerId
            oldPlayerId = oldPlayer.playerId
            prefix = CacheService.PREFIXES.PLAYER_MIGRATE
            key = "#{prefix}:#{oldPlayerId}"
            CacheService.runOnce key, =>
              oldPlayer.id = oldPlayerId
              userPlayer = {userId, gameId, playerId: oldPlayerId}
              if oldPlayer.verifiedUserId is userId
                userPlayer.isVerified = true

              Promise.all [
                unless userPlayerExists
                  UserPlayer.create userPlayer
                @GamePlayers[gameId].create oldPlayer
              ]
      else
        Promise.resolve null

  getByUserIdAndGameId: (userId, gameId, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.USER_PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, ->
        UserPlayer.getByUserIdAndGameId userId, gameId
      , {ignoreNull: true}
      # TODO: remove after ~June 2017?
      .then (userPlayer) =>
        userPlayerExists = Boolean userPlayer?.playerId
        (if userPlayerExists
          @GamePlayers[gameId].getById userPlayer?.playerId
        else
          Promise.resolve null
        )
        .then (player) =>
          if player
            _.defaults {isVerified: userPlayer.isVerified}, player
          else
            @migrate {userId, gameId, userPlayerExists}
            .then =>
              unless retry
                @getByUserIdAndGameId userId, gameId, {retry: true}

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_USER_ID_GAME_ID
      cacheKey = "#{prefix}:#{userId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  updateByPlayerIdAndGameId: (playerId, gameId, diff) =>
    @GamePlayers[gameId].updateById playerId, diff

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

  getStaleByGameId: (gameId, {staleTimeS, type, limit}) =>
    @GamePlayers[gameId].getStale {staleTimeS, type, limit}

  removeUserId: (userId, gameId) ->
    unless userId
      console.log 'rm userId missing', userId
      return Promise.resolve null
    UserPlayer.deleteByUserIdAndGameId userId, gameId

  updateByPlayerIdsAndGameId: (playerIds, gameId, diff) =>
    @GamePlayers[gameId].updateAllByIds playerIds, diff

  deleteByPlayerIdAndGameId: (playerId, gameId) =>
    @GamePlayers[gameId].deleteById playerId


module.exports = PlayerModel
