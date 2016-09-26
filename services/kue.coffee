kue = require 'kue'
Redis = require 'ioredis'
_ = require 'lodash'

config = require '../config'

KUE_SHUTDOWN_TIME_MS = 2000
STUCK_JOB_INTERVAL_MS = 3000

q = kue.createQueue {
  redis: {
    # kue makes 2 instances
    # http://stackoverflow.com/questions/30944960/kue-worker-with-with-createclientfactory-only-subscriber-commands-may-be-used
    createClientFactory: ->
      if config.ENV is config.ENVS.DEV and config.REDIS.NODES.length is 1
        new Redis {
          port: config.REDIS.PORT
          host: config.REDIS.NODES[0]
        }
      else
        new Redis.Cluster _.filter(config.REDIS.NODES)
  }
}

q.on 'error', (err) ->
  console.log err

q.watchStuckJobs STUCK_JOB_INTERVAL_MS

process.once 'SIGTERM', (sig) ->
  q.shutdown KUE_SHUTDOWN_TIME_MS, (err) ->
    console.log 'Kue shutdown: ', err or ''
    process.exit 0

module.exports = q
