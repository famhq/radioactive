_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'

CacheService = require '../services/cache'
Player = require '../models/player'
FortniteApiService = require '../services/fortnite_api'
config = require '../config'

defaultEmbed = []

GAME_KEY = 'fortnite'

class FortnitePlayerCtrl
  setByPlayerId: ({playerId, isUpdate}, {user}) =>
    (if isUpdate
      Player.removeUserId user.id, GAME_KEY
    else
      Promise.resolve null
    )
    .then ->
      Player.getByUserIdAndGameKey user.id, GAME_KEY
    .then (existingPlayer) =>
      @refreshByPlayerId {
        playerId, isUpdate, userId: user.id, priority: 'high'
      }, {user}

  refreshByPlayerId: ({playerId, userId, isLegacy, priority}, {user}) ->
    playerId = playerId.toLowerCase()

    isValidId = FortniteApiService.isValidId playerId
    unless isValidId
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.FORTNITE_REFRESH_PLAYER_ID_LOCK}:#{playerId}"
    # getting logs of multiple refreshes in same second - not sure why. this
    # should "fix". multiple at same time causes actions on matches
    # to be duplicated
    CacheService.lock key, ->
      # console.log 'refresh', playerId
      Player.getByUserIdAndGameKey user.id, GAME_KEY
      .then (mePlayer) ->
        if mePlayer?.id is playerId
          userId = user.id
        Player.upsertByPlayerIdAndGameKey playerId, GAME_KEY, {
          lastQueuedTime: new Date()
        }

        Promise.all [
          FortniteApiService.getPlayerDataById playerId
          Player.getByPlayerIdAndGameKey playerId, GAME_KEY
        ]
        .then ([playerData, existingPlayer]) ->
          unless playerData
            throw new Error 'username not found'
          diff = {
            data: _.defaultsDeep(
              playerData
              existingPlayer?.data or {}
            )
            lastUpdateTime: new Date()
          }
          # NOTE: any time you update, keep in mind scylla replaces
          # entire fields (data), so need to merge with old data manually
          Player.upsertByPlayerIdAndGameKey playerId, GAME_KEY, diff, {userId}
          .catch (err) ->
            console.log 'upsert err', err
            null

        .catch ->
          router.throw {
            status: 400, info: 'unable to find that username (typo?)'
            ignoreLog: true
          }
      .then ->
        return null
    , {expireSeconds: 5, unlockWhenCompleted: true}

  updateAutoRefreshDebug: ->
    console.log '============='
    console.log 'process url called'
    console.log '============='
    ClashRoyalePlayerService.updateAutoRefreshPlayers()

module.exports = new FortnitePlayerCtrl()
