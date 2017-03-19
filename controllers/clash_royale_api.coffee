_ = require 'lodash'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
UserGameData = require '../models/user_game_data'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
GameRecord = require '../models/game_record'
config = require '../config'

defaultEmbed = []

class ClashRoyaleAPICtrl
  refreshByPlayerTag: ({playerTag}, {user}) ->
    playerTag = playerTag.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    console.log 'refresh', playerTag
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

  updatePlayerMatches: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, matches} = body
      unless tag
        return
      console.log 'update matches', tag, matches.length
      # TODO: problem with this is if job errors, that user never gets updated
      # ever again
      # UserGameData.upsertByPlayerIdAndGameId tag, config.CLASH_ROYALE_ID, {
      #   isQueued: false
      # }
      ClashRoyaleAPIService.updatePlayerMatches {tag, matches}

  process: ->
    ClashRoyaleAPIService.process()

module.exports = new ClashRoyaleAPICtrl()
