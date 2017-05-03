_ = require 'lodash'
kue = require 'kue'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
ClashRoyalePlayerService = require './clash_royale_player'
ClashRoyaleClanService = require './clash_royale_clan'
config = require '../config'

# TODO: make separate lib, used by cr-api

# concurrency is multiplied by number of replicas (3 as of 4/11/2017)
# higher concurrency means more load on rethink nodes, but less on rethink
# proxies / radioactive (since it's split evenly between replicas)
# 12 cpus
TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrencyPerCpu: 1}
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES}":
    {fn: ClashRoyalePlayerService.processUpdatePlayerMatches, concurrencyPerCpu: 2}
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA}":
    {fn: ClashRoyalePlayerService.processUpdatePlayerData, concurrencyPerCpu: 1}
  "#{KueCreateService.JOB_TYPES.UPDATE_CLAN_DATA}":
    {fn: ClashRoyaleClanService.processUpdateClan, concurrencyPerCpu: 1}

class KueRunnerService
  listen: ->
    console.log 'listening to kue'
    _.forEach TYPES, ({fn, concurrencyPerCpu}, type) ->
      KueService.process type, concurrencyPerCpu, (job, ctx, done) ->
        # KueCreateService.setCtx type, ctx
        fn job.data
        .then (response) ->
          done null, response
        .catch (err) ->
          console.log 'err', err
          done err

module.exports = new KueRunnerService()
