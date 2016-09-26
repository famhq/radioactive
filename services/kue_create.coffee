_ = require 'lodash'
Promise = require 'bluebird'
log = require 'loga'
kue = require 'kue'

KueService = require './kue'
CacheService = require './cache'
config = require '../config'

RUNNER_ERROR_DELAY_MS = 1000
DEFAULT_PRIORITY = 0
DEFAULT_TTL_MS = 100000000 # 28 hours, sufficiently large for most tasks
IDLE_PROCESS_KILL_TIME_MS = 300 * 1000 # 5 min
PAUSE_EXTEND_BUFFER_MS = 5000
CLEANUP_TIME_MS = 30000

JOB_TYPES =
  DEFAULT: 'pulsar:default'
  BOT_PROCESS_MESSAGE: 'pulsar:bot:process_message'
  BOT_DISCORD_SEND_MESSAGE: 'pulsar:bot:discord_send_message'
  BOT_TELEGRAM_SEND_MESSAGE: 'pulsar:bot:telegram_send_message'
  BOT_MESSENGER_SEND_MESSAGE: 'pulsar:bot:messenger_send_message'
  BOT_KIK_SEND_MESSAGES: 'pulsar:bot:kik_send_message'
  BOT_FREE_CHEST: 'pulsar:bot:free_chest'
  INDECENCY_END_ROUND: 'pulsar:indecency:end_round'
  GAME_VOTE: 'pulsar:bot:game_vote'
  BATCH_NOTIFICATION: 'pulsar:batch_notification'


class KueCreateService
  JOB_TYPES: JOB_TYPES

  constructor: ->
    @workers = {} # pause/resume with this

  clean: ->
    console.log 'clean'
    types = ['failed', 'complete', 'inactive', 'active']
    Promise.map types, (type) ->
      new Promise (resolve, reject) ->
        kue.Job.rangeByState type, 0, -1, 'asc', (err, selectedJobs) ->
          if err
            reject err
          resolve Promise.each selectedJobs, (job) ->
            job.remove (err) ->
              if err
                reject(err)
              else
                resolve()

  pauseWorker: (kueWorkerId, {killTimeMs, resumeAfterTimeMs}) =>
    if resumeAfterTimeMs
      extendMs = resumeAfterTimeMs + killTimeMs + PAUSE_EXTEND_BUFFER_MS
      worker?.lock?.extend? extendMs

    killTimeMs ?= 5000
    worker = @workers[kueWorkerId]
    console.log 'pause worker', Boolean worker
    new Promise (resolve, reject) ->
      unless worker
        console.log 'skip pause'
        reject new Error('worker doesn\'t exist')
      try
        console.log worker?.id
        worker?.ctx?.pause? killTimeMs, (err) ->
          if err
            reject err
          else
            resolve()
      catch err
        console.log err
    .then ->
      if resumeAfterTimeMs?
        # TODO: use redis/queue for this instead of setTimeout?
        setTimeout ->
          try
            console.log 'resume worker', worker?.id
            worker?.ctx?.resume?()
          catch err
            console.log err
        , Math.max resumeAfterTimeMs, killTimeMs

  killWorker: (kueWorkerId, {killTimeMs} = {}) =>
    killTimeMs ?= 5000
    console.log 'kill worker'
    new Promise (resolve, reject) =>
      worker = @workers[kueWorkerId]
      try
        worker?.ctx?.pause? killTimeMs, resolve
      catch err
        console.log 'kill err', err
    .catch (err) ->
      console.log 'kill promise err', err
    .then =>
      delete @workers[kueWorkerId]

  # FIFO, ability to pause worker for chat/kueWorkerId
  listenOnce: (kueWorkerId) =>
    key = "#{CacheService.LOCK_PREFIXES.KUE_PROCESS}:#{kueWorkerId}"
    expireSeconds = if config.ENV is config.ENVS.DEV then 3 else 30
    CacheService.lock key, (lock) =>
      # FIXME FIXME: don't keep repeating failed message
      lastUpdateTime = Date.now()
      clearExtendInterval = -> clearInterval extendInterval
      extendInterval = setInterval =>
        if Date.now() - lastUpdateTime > IDLE_PROCESS_KILL_TIME_MS
          @killWorker kueWorkerId
          .then clearExtendInterval
          .catch clearExtendInterval
        else
          lock.extend expireSeconds * 1000
          .catch clearExtendInterval
      , 1000 * expireSeconds / 2

      KueService.process kueWorkerId, 1, (job, ctx, done) =>
        # we queue this fn up again so it can be run on any
        # process/server, in case we have one chatId that is too heavy for a CPU
        lastUpdateTime = Date.now()
        @workers[kueWorkerId] = {ctx, lock, id: job.id}
        @createJob _.defaults {isSynchronous: false}, job.data
        .then ->
          done()
        .catch (err) ->
          done err
    , {
      expireSeconds: expireSeconds
    }

  createJob: (options) =>
    {job, priority, ttlMs, delayMs, type, isSynchronous, kueWorkerId,
      maxAttempts, backoff, waitForCompletion} = options

    new Promise (resolve, reject) =>
      unless type? and _.includes _.values(JOB_TYPES), type
        throw new Error 'Must specify a valid job type ' + type
      # create process for this queue, locked so only one worker manages it
      # (so it's fifo, one at a time)
      (if isSynchronous
        kueWorkerId ?= 'default_worker'
        @listenOnce kueWorkerId
        .then ->
          KueService.create kueWorkerId, options
      else
        kueJob = KueService.create type, _.defaults(job, {
          title: type # for kue dashboard
        })
        Promise.resolve kueJob)
      .then (kueJob) ->

        priority ?= DEFAULT_PRIORITY
        ttlMs ?= DEFAULT_TTL_MS
        delayMs ?= 0

        kueJob
        .priority DEFAULT_PRIORITY
        .ttl ttlMs
        .removeOnComplete true

        if delayMs
          kueJob = kueJob.delay delayMs

        if maxAttempts
          kueJob = kueJob.attempts maxAttempts

        if backoff
          kueJob = kueJob.backoff {delay: backoff, type: 'fixed'}

        kueJob.save (err) ->
          if err
            reject err
          else if not waitForCompletion
            resolve()

        if waitForCompletion
          kueJob.on 'complete', resolve
          kueJob.on 'failed', reject

module.exports = new KueCreateService()
