_ = require 'lodash'
kue = require 'kue'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
ProductService = require './product'
ClashRoyaleAPIService = require './clash_royale_api'
ClashRoyalePlayerService = require './clash_royale_player'
config = require '../config'

# TODO: make separate lib, used by cr-api

# doing 33 per second instead of 96. each must be taking ~3s instead of 1

# concurrency is multiplied by number of cpus & replicas (6 as of 4/11/2017)
# higher concurrency means more load on rethink nodes, but less on rethink
# proxies / radioactive (since it's split evenly between replicas)
# 36 cpus
TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrencyPerCpu: 1}
  "#{KueCreateService.JOB_TYPES.PRODUCT_UNLOCKED}":
    {fn: ProductService.productUnlocked, concurrencyPerCpu: 10}
  "#{KueCreateService.JOB_TYPES.AUTO_REFRESH_PLAYER}":
    {
      fn: ({playerId}) ->
        ClashRoyalePlayerService.updatePlayerById playerId, {
          priority: 'normal'
          isAuto: true
        }
      concurrencyPerCpu: 3 # TODO: 6
    }
  # ideally we'd throttle this at 300 per second, but we can't do that
  # sort of throttling with kue (or any redis-backed lib from what I can tell).
  # so we estimate based on average request time and concurrent requests.

  # alternative is to wait until we get a rate limit error, then pause the
  # queue workers for a bit (we did this with the kik bot)

  # eg 500 request time = 2 req per job per second
  # 300 / 2 = 150 concurrent jobs. currently have 36 cpus. 150/36 = 4

  "#{KueCreateService.JOB_TYPES.API_REQUEST}":
    {fn: ClashRoyaleAPIService.processRequest, concurrencyPerCpu: 2} # TODO: 4

class KueRunnerService
  listen: ->
    console.log 'listening to kue'
    _.forEach TYPES, ({fn, concurrencyPerCpu}, type) ->
      KueService.process type, concurrencyPerCpu, (job, ctx, done) ->
        # KueCreateService.setCtx type, ctx
        try
          fn job.data
          .then (response) ->
            done null, response
          .catch (err) ->
            console.log 'kue err', err
            done err
        catch err
          done err

module.exports = new KueRunnerService()
