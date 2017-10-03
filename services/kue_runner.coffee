_ = require 'lodash'
kue = require 'kue'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
ClashRoyaleAPIService = require './clash_royale_api'
ClashRoyalePlayerService = require './clash_royale_player'
config = require '../config'

# TODO: make separate lib, used by cr-api

# concurrency is multiplied by number of replicas (3 as of 4/11/2017)
# higher concurrency means more load on rethink nodes, but less on rethink
# proxies / radioactive (since it's split evenly between replicas)
# 24 cpus
TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrencyPerCpu: 1}
  "#{KueCreateService.JOB_TYPES.AUTO_REFRESH_PLAYER}":
    {
      fn: ({playerId}) ->
        ClashRoyalePlayerService.updatePlayerById playerId, {priority: 'normal'}
      concurrencyPerCpu: 5
    }
  # ideally we'd throttle this at 300 per second, but we can't do that
  # sort of throttling with kue (or any redis-backed lib from what I can tell).
  # so we estimate based on average request time and concurrent requests.

  # alternative is to wait until we get a rate limit error, then pause the
  # queue workers for a bit (we did this with the kik bot)

  # eg 250ms request time = 4 req per job per second
  # 300 / 4 = 75 concurrent jobs. currently have 24 cpus. 75/24 = 3

  "#{KueCreateService.JOB_TYPES.API_REQUEST}":
    {fn: ClashRoyaleAPIService.processRequest, concurrencyPerCpu: 3}

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
          console.log 'kue err', err
          done err

module.exports = new KueRunnerService()
