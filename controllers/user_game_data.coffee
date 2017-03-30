_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserData = require '../models/user_data'
UserGameData = require '../models/user_game_data'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
ClashRoyaleAPIService = require '../services/clash_royale_api'
KueCreateService = require '../services/kue_create'
CacheService = require '../services/cache'
config = require '../config'

defaultEmbed = []

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
ONE_MINUTE_SECONDS = 60

class UserGameDataCtrl
  getByUserIdAndGameId: ({userId, gameId}, {user}) ->
    gameId or= config.CLASH_ROYALE_ID

    UserGameData.getByUserIdAndGameId userId, gameId

  search: ({playerId}, {user}) ->
    playerId = playerId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = playerId.match /^[0289PYLQGRJCUV]+$/
    console.log 'search', playerId
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag'}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{playerId}"
    CacheService.preferCache key, ->
      UserGameData.getByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID
      .then (userGameData) ->
        if userGameData?.userIds?[0]
          userGameData
        else
          User.create {}
          .then ({id}) ->
            ClashRoyaleAPIService.refreshByPlayerTag playerId, {
              userId: id
              priority: 'normal'
            }
          .then ->
            UserGameData.getByPlayerIdAndGameId playerId, GAME_ID

    , {expireSeconds: TWELVE_HOURS_SECONDS}

  getTop: ->
    key = CacheService.KEYS.PLAYERS_TOP
    CacheService.preferCache key, ->
      ClashRoyaleTopPlayer.getAll()
      .then (topPlayers) ->
        playerIds = _.map topPlayers, 'playerId'
        UserGameData.getAllByPlayerIdsAndGameId(
          playerIds, config.CLASH_ROYALE_ID
        )
        .then (userGameDatas) ->
          players = _.map userGameDatas, (userGameData) ->
            topPlayer = _.find topPlayers, {playerId: userGameData.playerId}
            {rank: topPlayer?.rank, userGameData}
          _.orderBy players, 'rank'
    , {expireSeconds: ONE_MINUTE_SECONDS}

  getMeFollowing: ({}, {user}) ->
    key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING_PLAYERS}:#{user.id}"

    CacheService.preferCache key, ->
      UserData.getByUserId user.id
      .then (userData) ->
        followingIds = userData.followingIds
        UserGameData.getAllByUserIdsAndGameId(
          followingIds, config.CLASH_ROYALE_ID
        )
        .then (userGameDatas) ->
          players = _.map userGameDatas, (userGameData) ->
            {userGameData}
    , {expireSeconds: 1} # FIXME FIXME ONE_MINUTE_SECONDS}

module.exports = new UserGameDataCtrl()
