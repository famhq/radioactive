Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

KueCreateService = require './kue_create'
Clan = require '../models/clan'
config = require '../config'

PLAYER_DATA_TIMEOUT_MS = 10000
PLAYER_MATCHES_TIMEOUT_MS = 10000

processingM = 0
processingP = 0

class ClashRoyaleKue
  getPlayerDataByTag: (tag, {priority, skipCache} = {}) ->
    request "#{config.CR_API_URL}/players/#{tag}", {
      json: true
      qs:
        priority: priority
        skipCache: skipCache
    }
    .then (responses) ->
      responses?[0]
    .catch (err) ->
      console.log 'err playerDataByTag', err

  getPlayerMatchesByTag: (tag, {priority} = {}) ->
    request "#{config.CR_API_URL}/players/#{tag}/games", {
      json: true
      qs:
        priority: priority
    }
    .then (responses) ->
      responses?[0]
    .catch (err) ->
      console.log 'err playerMatchesByTag', err

  refreshByPlayerTag: (playerTag, {userId, priority} = {}) =>
    Promise.all [
      @getPlayerDataByTag playerTag, {priority}
      @getPlayerMatchesByTag playerTag, {priority}
    ]
    .then ([playerData, matches]) ->
      unless playerTag and playerData
        console.log 'update missing tag or data', playerTag, playerData
      KueCreateService.createJob {
        job: {userId: userId, tag: playerTag, playerData}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA
        ttlMs: PLAYER_DATA_TIMEOUT_MS
        priority: priority or 'high'
        waitForCompletion: true
      }
      .then ->
        KueCreateService.createJob {
          job: {tag: playerTag, matches, reqSynchronous: true}
          type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES
          ttlMs: PLAYER_MATCHES_TIMEOUT_MS
          priority: priority or 'high'
          waitForCompletion: true
        }
        .timeout PLAYER_MATCHES_TIMEOUT_MS
        .catch -> null

  getClanByTag: (tag, {priority} = {}) ->
    request "#{config.CR_API_URL}/clans/#{tag}", {
      json: true
      qs:
        priority: priority
    }
    .then (responses) ->
      responses?[0]
    .catch (err) ->
      console.log 'err clanByTag', err

  refreshByClanId: (clanId, {userId, priority} = {}) =>
    @getClanByTag clanId, {priority}
    .then (clan) ->
      KueCreateService.createJob {
        job: {userId: userId, tag: clanId, clan}
        type: KueCreateService.JOB_TYPES.UPDATE_CLAN_DATA
        priority: priority or 'high'
        waitForCompletion: true
      }
    .then ->
      Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        preferCache: true
      }
      .then ({id}) -> {id}

module.exports = new ClashRoyaleKue()
