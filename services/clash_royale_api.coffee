Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

UserGameData = require '../models/user_game_data'
Group = require '../models/group'
EmailService = require '../services/email'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 1000 # 1s
STALE_TIME_MS = 3600 * 12 # 12hr

class ClashAPIService
  getPlayerDataByTag: (tag) ->
    request "#{config.CR_API_URL}/players/#{tag}", {json: true}

  getPlayerGamesByTag: (tag) ->
    request "#{config.CR_API_URL}/players/#{tag}/games", {json: true}

  getClanDataByTag: (tag) ->
    request "#{config.CR_API_URL}/clans/#{tag}", {json: true}

  processPlayer: (player) =>
    @getPlayerData player.playerId
    .then ({trophies}) ->
      UserGameData.updateById player.id, {
        trophies: trophies
      }

  processClan: (clan) =>
    @getPlayerData clan.clanId
    .then ({trophies}) ->
      UserGameData.updateById clan.id, {
        trophies: trophies
      }

  process: =>
    start = Date.now()
    UserGameData.getStale {
      gameId: config.CLASH_ROYALE_ID, staleTimeMs: STALE_TIME_MS
    }
    .then (players) =>
      Promise.each players, @processPlayer
    .then ->
      Group.getStale {gameId: id, staleTimeMs: STALE_TIME_MS}
      .then (groups) =>
        Promise.each groups, @processClan

    .then ->
      timeToComplete = Date.now() - start
      if timeToComplete >= MAX_TIME_TO_COMPLETE_MS
        EmailService.send {
          to: EmailService.EMAILS.OPS
          subject: 'Clash API too slow'
          text: "Took longer than #{MAX_TIME_TO_COMPLETE_MS}ms"
        }


module.exports = new ClashAPIService()
