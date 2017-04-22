_ = require 'lodash'
kue = require 'kue'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
ClashRoyalePlayerService = require './clash_royale_player'
ClashRoyaleClanService = require './clash_royale_clan'
config = require '../config'

# concurrency is multiplied by number of replicas (3 as of 4/11/2017)
# higher concurrency means more load on rethink nodes, but less on rethink
# proxies / radioactive (since it's split evenly between replicas)
TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrency: 3}
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES}":
    {fn: ClashRoyalePlayerService.processUpdatePlayerMatches, concurrency: 1} # FIXME 4 or 10
  "#{KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA}":
    {fn: ClashRoyalePlayerService.processUpdatePlayerData, concurrency: 1} # FIXME 4 or 10
  "#{KueCreateService.JOB_TYPES.UPDATE_CLAN_DATA}":
    {fn: ClashRoyaleClanService.processUpdateClan, concurrency: 1} # FIXME 4 or 10

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
            console.log 'err', err
            done err

module.exports = new KueRunnerService()
