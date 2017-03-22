_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
User = require '../models/user'
UserGameData = require '../models/user_game_data'
UserGameDailyData = require '../models/user_game_daily_data'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
GameRecord = require '../models/game_record'
PushNotificationService = require '../services/push_notification'
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
      Promise.all [
        ClashRoyaleAPIService.getPlayerDataByTag playerTag
        ClashRoyaleAPIService.getPlayerMatchesByTag playerTag
      ]
    .then ([playerData, matches]) ->
      ClashRoyaleAPIService.updatePlayerData {
        userId: user.id, playerData, tag: playerTag
      }
      .then ->
        ClashRoyaleAPIService.updatePlayerMatches {
          matches, tag: playerTag
        }
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
      Promise.all [
        ClashRoyaleAPIService.updatePlayerData {tag, playerData}
        UserGameDailyData.getByPlayerIdAndGameId tag, config.CLASH_ROYALE_ID
      ]
      .then ([userGameData, userGameDailyData]) ->
        if userGameData and userGameDailyData?.data
          splits = userGameDailyData.data.splits
          stats = _.reduce splits, (aggregate, split, gameType) ->
            aggregate.wins += split.wins
            aggregate.losses += split.losses
            aggregate
          , {wins: 0, losses: 0}
          userGameDailyData.deleteById userGameDailyData.id
          Promise.map userGameData.userIds, User.getById
          .map (user) ->
            PushNotificationService.send user, {
              title: 'Daily recap'
              type: PushNotificationService.TYPES.DAILY_RECAP
              url: "https://#{config.SUPERNOVA_HOST}"
              text: "#{stats.wins} wins, #{stats.losses} losses. Post in chat
                    what else you want to see in the recap :)"
              data: {path: '/'}
            }
          null

  updatePlayerMatches: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, matches} = body
      unless tag
        return
      # TODO: problem with this is if job errors, that user never gets updated
      # ever again
      # UserGameData.upsertByPlayerIdAndGameId tag, config.CLASH_ROYALE_ID, {
      #   isQueued: false
      # }
      ClashRoyaleAPIService.updatePlayerMatches {tag, matches}

  process: ->
    # this triggers daily recap push notification
    # ClashRoyaleAPIService.updateStalePlayerData {force: true}
    ClashRoyaleAPIService.updateStalePlayerMatches {force: true}

module.exports = new ClashRoyaleAPICtrl()
