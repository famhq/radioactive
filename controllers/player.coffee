_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserData = require '../models/user_data'
Player = require '../models/player'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
ClashRoyaleKueService = require '../services/clash_royale_kue'
KueCreateService = require '../services/kue_create'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.PLAYER.CHEST_CYCLE
  EmbedService.TYPES.PLAYER.IS_UPDATABLE
]

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
ONE_MINUTE_SECONDS = 60

class PlayerCtrl
  getByUserIdAndGameId: ({userId, gameId}, {user}) ->
    unless userId
      return

    gameId or= config.CLASH_ROYALE_ID

    start = Date.now()
    # TODO: cache, but need to clear the cache whenever player is updated...
    Player.getByUserIdAndGameId userId, gameId #, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed}

  search: ({playerId}, {user, headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    playerId = playerId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = playerId.match /^[0289PYLQGRJCUV]+$/
    console.log 'search', playerId, ip
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{playerId}"
    CacheService.preferCache key, ->
      Player.getByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID
      .then EmbedService.embed {
        embed: [EmbedService.TYPES.PLAYER.USER_IDS]
        gameId: config.CLASH_ROYALE_ID
      }
      .then (player) ->
        if player?.userIds?[0]
          player
        else
          User.create {}
          .then ({id}) ->
            ClashRoyaleKueService.refreshByPlayerTag playerId, {
              userId: id
              priority: 'normal'
            }
          .then ->
            Player.getByPlayerIdAndGameId playerId, GAME_ID

    , {expireSeconds: TWELVE_HOURS_SECONDS}

  getTop: ->
    key = CacheService.KEYS.PLAYERS_TOP
    CacheService.preferCache key, ->
      ClashRoyaleTopPlayer.getAll()
      .then (topPlayers) ->
        playerIds = _.map topPlayers, 'playerId'
        Player.getAllByPlayerIdsAndGameId(
          playerIds, config.CLASH_ROYALE_ID
        )
        .map EmbedService.embed {
          embed: [EmbedService.TYPES.PLAYER.USER_IDS]
          gameId: config.CLASH_ROYALE_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            topPlayer = _.find topPlayers, {playerId: player.id}
            {rank: topPlayer?.rank, player}
          _.orderBy players, 'rank'
    , {expireSeconds: ONE_MINUTE_SECONDS}

  getMeFollowing: ({}, {user}) ->
    key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING_PLAYERS}:#{user.id}"

    CacheService.preferCache key, ->
      UserData.getByUserId user.id
      .then (userData) ->
        followingIds = userData.followingIds
        Player.getAllByUserIdsAndGameId(
          followingIds, config.CLASH_ROYALE_ID
        )
        .map EmbedService.embed {
          embed: [EmbedService.TYPES.PLAYER.USER_IDS]
          gameId: config.CLASH_ROYALE_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            {player}
    , {expireSeconds: 1} # FIXME FIXME ONE_MINUTE_SECONDS}

module.exports = new PlayerCtrl()
