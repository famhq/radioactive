_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
KueCreateService = require '../services/kue_create'
User = require '../models/user'
UserGameData = require '../models/user_game_data'
UserGameDailyData = require '../models/user_game_daily_data'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
GameRecord = require '../models/game_record'
config = require '../config'

defaultEmbed = []

class ClashRoyaleAPICtrl
  refreshByPlayerTag: ({playerTag}, {user}) ->
    playerTag = playerTag.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = playerTag.match /^[0289PYLQGRJCUV]+$/
    console.log 'refresh', playerTag
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag'}

    UserGameData.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
    .then (userGameData) ->
      unless userGameData?.playerId
        Promise.all [
          ClashRoyaleUserDeck.duplicateByPlayerId playerTag, user.id
          GameRecord.duplicateByPlayerId playerTag, user.id
        ]
    .then ->
      ClashRoyaleAPIService.refreshByPlayerTag playerTag, {userId: user.id}
    .then ->
      return null

  # should only be called once daily
  updatePlayerData: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, playerData} = body
      unless tag
        return
      KueCreateService.createJob {
        job: {tag, playerData, isDaily: true}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA
        priority: 'low'
      }

  updatePlayerMatches: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, matches} = body
      unless tag
        return
      KueCreateService.createJob {
        job: {tag, matches}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES
        priority: 'low'
      }

  queuePlayerData: ({params}) ->
    console.log 'single queue', params.tag
    request "#{config.CR_API_URL}/players/#{params.tag}", {
      json: true
      qs:
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
    }

  queuePlayerMatches: ({params}) ->
    console.log 'single queue', params.tag
    request "#{config.CR_API_URL}/players/#{params.tag}/games", {
      json: true
      qs:
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
    }

  updateTopPlayers: ->
    ClashRoyaleAPIService.updateTopPlayers()

  process: ->
    console.log '============='
    console.log 'process url called'
    console.log '============='
    # this triggers daily recap push notification
    # ClashRoyaleAPIService.updateStalePlayerData {force: true}
    ClashRoyaleAPIService.updateStalePlayerMatches {force: true}

module.exports = new ClashRoyaleAPICtrl()
