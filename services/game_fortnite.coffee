Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'
Fortnite = require 'fortnite-api'

KueCreateService = require './kue_create'
CacheService = require './cache'
Player = require '../models/player'
config = require '../config'

API_REQUEST_TIMEOUT_MS = 10000
ONE_DAY_SECONDS = 3600 * 24
IS_DEBUG = true

class FortniteService
  constructor: ->
    if IS_DEBUG or config.ENV is config.ENVS.PROD and not config.IS_STAGING
      @fortniteApi = new Fortnite [
        config.FORTNITE_EMAIL
        config.FORTNITE_PASSWORD
        config.FORTNITE_CLIENT_LAUNCHER_TOKEN
        config.FORTNITE_CLIENT_TOKEN
      ]
      @fortniteApi.login()
      .catch (err) ->
        console.log 'fortnite err', err

  isValidByPlayerId: (id) ->
    id.match /^(pc|ps4|xb1)\:(.*?)+$/

  formatByPlayerId: (playerId) -> playerId

  request: ({method, username, network, priority} = {}) ->
    KueCreateService.createJob {
      job: {method, username, network}
      type: KueCreateService.JOB_TYPES.FORTNITE_API_REQUEST
      ttlMs: API_REQUEST_TIMEOUT_MS
      priority: priority
      waitForCompletion: true
    }

  processRequest: ({method, username, network}) =>
    unless method in ['getStatsBR']
      throw new Error 'invalid method'

    @fortniteApi[method] username, network
    .then (response) ->
      response
    .catch (err) ->
      console.log 'fornite get err', err

  getNetworkAndUsernameById: (id) ->
    index = id.indexOf(':')
    network = id.substr(0, index)
    username = id.substr index + 1
    {network, username}

  getPlayerDataByPlayerId: (id, {priority, skipCache} = {}) =>
    unless @isValidByPlayerId id
      throw new Error 'invalid tag'

    {network, username} = @getNetworkAndUsernameById id

    @request {
      method: 'getStatsBR', username, network
    }

  updatePlayerByPlayerId: (playerId, {userId} = {}) =>
    Promise.all [
      @getPlayerDataByPlayerId playerId
      Player.getByPlayerIdAndGameKey playerId, 'fortnite'
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
      Player.upsertByPlayerIdAndGameKey playerId, 'fortnite', diff, {userId}
      .catch (err) ->
        console.log 'upsert err', err
        null

module.exports = new FortniteService()
