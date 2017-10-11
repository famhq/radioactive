_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserFollower = require '../models/user_follower'
Player = require '../models/player'
ClashRoyalePlayer = require '../models/clash_royale_player'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
UserPlayer = require '../models/user_player'
ClashRoyaleAPIService = require '../services/clash_royale_api'
ClashRoyalePlayerService = require '../services/clash_royale_player'
CacheService = require '../services/cache'
TagConverterService = require '../services/tag_converter'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.PLAYER.HI
  EmbedService.TYPES.PLAYER.COUNTERS
]
userIdsEmbed = [
  EmbedService.TYPES.PLAYER.USER_IDS
  EmbedService.TYPES.PLAYER.VERIFIED_USER
]

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
TEN_MINUTES_SECONDS = 10 * 60
ONE_MINUTE_SECONDS = 60

class PlayerCtrl
  getByUserIdAndGameId: ({userId, gameId}, {user}) ->
    unless userId
      return

    gameId or= GAME_ID

    # TODO: cache, but need to clear the cache whenever player is updated...
    Player.getByUserIdAndGameId userId, gameId #, {preferCache: true}
    .tap (player) ->
      # TODO: rm ~early nov
      if player
        key = "playermigrate7:#{player.id}"
        CacheService.runOnce key, ->
          if user.joinTime?.getTime() < 1507106200492 # oct 3
            ClashRoyalePlayer.migrate player.id
            .then ->
              Player.getByPlayerIdAndGameId player.id, gameId


    .then EmbedService.embed {embed: defaultEmbed}

  getIsAutoRefreshByPlayerIdAndGameId: ({playerId, gameId}) ->
    Player.getIsAutoRefreshByPlayerIdAndGameId playerId, gameId

  getByPlayerIdAndGameId: ({playerId, gameId}, {user}) ->
    unless playerId
      return

    playerId = ClashRoyaleAPIService.formatHashtag playerId

    # TODO: cache, but need to clear the cache whenever player is updated...
    Player.getByPlayerIdAndGameId playerId, gameId #, {preferCache: true}
    .then (player) ->
      if player
        return player
      else
        ClashRoyalePlayerService.updatePlayerById playerId, {
          priority: 'normal'
        }
        .then ->
          Player.getByPlayerIdAndGameId playerId, gameId
    .then EmbedService.embed {embed: defaultEmbed}

  setAutoRefreshByGameId: ({gameId}, {user}) ->
    key = "#{CacheService.LOCK_PREFIXES.SET_AUTO_REFRESH}:#{gameId}:#{user.id}"
    CacheService.lock key, ->
      Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
      .then EmbedService.embed {
        embed: [EmbedService.TYPES.PLAYER.VERIFIED_USER]
        gameId: config.CLASH_ROYALE_ID
      }
      .then (player) ->
        if player?.verifiedUser?.id is user.id
          Player.setAutoRefreshByPlayerIdAndGameId(
            player.id, config.CLASH_ROYALE_ID
          )
    , {expireSeconds: TEN_MINUTES_SECONDS}

  # verifyMe: ({gold, lo}, {user}) ->
  #   Player.getByUserIdAndGameId user.id, GAME_ID
  #   .then (player) ->
  #     hiLo = TagConverterService.getHiLoFromTag player.id
  #     unless "#{lo}" is "#{hiLo.lo}"
  #       router.throw {status: 400, info: 'invalid player id', ignoreLog: true}
  #
  #     ClashRoyaleAPIService.getPlayerDataByTag player.id, {
  #       priority: 'high', skipCache: true, isLegacy: true
  #     }
  #     .then (playerData) ->
  #       unless "#{gold}" is "#{playerData?.gold}"
  #         router.throw {status: 400, info: 'invalid gold', ignoreLog: true}
  #
  #       # mark others unverified
  #       UserPlayer.updateByPlayerIdAndGameId player.id, GAME_ID, {
  #         isVerified: false
  #       }
  #     .then ->
  #       UserPlayer.updateByUserIdAndPlayerIdAndGameId(
  #         user.id
  #         player.id
  #         GAME_ID
  #         {isVerified: true}
  #       )
  #       .tap ->
  #         Player.setAutoRefreshByPlayerIdAndGameId player.id, GAME_ID
  #
  #         key = "#{CacheService.PREFIXES.PLAYER_VERIFIED_USER}:#{player.id}"
  #         CacheService.deleteByKey key

  search: ({playerId}, {user, headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    playerId = playerId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = ClashRoyaleAPIService.isValidTag playerId
    console.log 'search', playerId, ip
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{playerId}"
    CacheService.preferCache key, ->
      Player.getByPlayerIdAndGameId playerId, GAME_ID
      .then EmbedService.embed {
        embed: userIdsEmbed
        gameId: GAME_ID
      }
      .then (player) ->
        if player?.userIds?[0]
          player.userId = player.verifiedUser?.id or player.userIds?[0]
          delete player.userIds
          player
        else
          User.create {}
          .then ({id}) ->
            start = Date.now()
            ClashRoyalePlayerService.updatePlayerById playerId, {
              userId: id
              priority: 'normal'
            }
            .then ->
              Player.getByPlayerIdAndGameId playerId, GAME_ID
              .then EmbedService.embed {
                embed: userIdsEmbed
                gameId: GAME_ID
              }
              .then (player) ->
                if player?.userIds?[0]
                  player.userId = player.verifiedUser?.id or player.userIds?[0]
                  delete player.userIds
                  player

    , {expireSeconds: TWELVE_HOURS_SECONDS}

  getTop: ->
    key = CacheService.KEYS.PLAYERS_TOP
    CacheService.preferCache key, ->
      ClashRoyaleTopPlayer.getAll()
      .then (topPlayers) ->
        playerIds = _.map topPlayers, 'playerId'
        Player.getAllByPlayerIdsAndGameId(
          playerIds, GAME_ID
        )
        .map EmbedService.embed {
          embed: userIdsEmbed
          gameId: GAME_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            player.userId = player.verifiedUser?.id or player.userIds?[0]
            delete player.userIds
            topPlayer = _.find topPlayers, {playerId: player.id}
            {rank: topPlayer?.rank, player}
          _.orderBy players, 'rank'
    , {expireSeconds: ONE_MINUTE_SECONDS}

  getMeFollowing: ({}, {user}) ->
    key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING_PLAYERS}:#{user.id}"

    CacheService.preferCache key, ->
      UserFollower.getAllByUserId user.id
      .map (userFollower) ->
        userFollower.followingId
      .then (followingIds) ->
        Player.getAllByUserIdsAndGameId(
          followingIds, GAME_ID
        )
        .map EmbedService.embed {
          embed: userIdsEmbed
          gameId: GAME_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            player.userId = player.verifiedUser?.id or player.userIds?[0]
            delete player.userIds
            {player}
    , {expireSeconds: ONE_MINUTE_SECONDS}

module.exports = new PlayerCtrl()
