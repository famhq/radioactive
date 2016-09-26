_ = require 'lodash'
kue = require 'kue'
Promise = require 'bluebird'
log = require 'loga'

KueService = require './kue'
KueCreateService = require './kue_create'
BroadcastService = require './broadcast'
config = require '../config'

TYPES =
  "#{KueCreateService.JOB_TYPES.BATCH_NOTIFICATION}":
    {fn: BroadcastService.batchNotify, concurrency: 3}


class KueRunnerService
  listen: ->
    if config.ENV isnt config.ENVS.DEV or config.REDIS.NODES.length is 1
      console.log 'listening to kue'
      _.forEach TYPES, ({fn, concurrency}, type) ->
        KueService.process type, concurrency, (job, ctx, done) ->
          # KueCreateService.setCtx type, ctx
          fn job.data
          .then ->
            done()
          .catch (err) ->
            done err

module.exports = new KueRunnerService()
