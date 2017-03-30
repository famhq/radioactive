_ = require 'lodash'
kue = require 'kue'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
ClashRoyaleApiService = require './clash_royale_api'
config = require '../config'

TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrency: 3}
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES}":
    {fn: ClashRoyaleApiService.updatePlayerMatches, concurrency: 4}
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA}":
    {fn: ClashRoyaleApiService.processUpdatePlayerData, concurrency: 4}

class KueRunnerService
  listen: ->
    if config.ENV isnt config.ENVS.DEV or config.REDIS.NODES.length is 1
      console.log 'listening to kue'
      _.forEach TYPES, ({fn, concurrency}, type) ->
        KueService.process type, concurrency, (job, ctx, done) ->
          # KueCreateService.setCtx type, ctx
          fn job.data
          .then (response) ->
            done null, response
          .catch (err) ->
            done err

module.exports = new KueRunnerService()
