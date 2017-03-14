_ = require 'lodash'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
UserGameData = require '../models/user_game_data'
config = require '../config'

defaultEmbed = []

class ClashRoyaleAPICtrl
  refreshByPlayerTag: ({playerTag}, {user}) ->
    playerTag = playerTag.trim().toUpperCase()
                .replace '#', ''
                .replace 'O', '0' # replace capital O with zero

    ClashRoyaleAPIService.getPlayerDataByTag playerTag
    .then ({matches, playerData}) ->
      ClashRoyaleAPIService.updatePlayer {userId: user.id, matches, playerData}
    .then ->
      return null

  updatePlayer: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    console.log 'update player'
    if isPrivate and body.secret is config.CR_API_SECRET
      {playerData, matches} = body
      unless playerData?.tag
        return
      ClashRoyaleAPIService.updatePlayer {matches, playerData}

  process: ->
    ClashRoyaleAPIService.process()

module.exports = new ClashRoyaleAPICtrl()
