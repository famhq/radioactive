_ = require 'lodash'
Promise = require 'bluebird'

r = require './rethinkdb'
User = require '../models/user'
CacheService = require './cache'
KueCreateService = require './kue_create'
PushNotificationService = require './push_notification'
config = require '../config'

AMOUNT_PER_BATCH = 100
TIME_PER_BATCH_SECONDS = 10
FIVE_MINUTE_SECONDS = 5 * 60

class BroadcastService
  failSafe: ->
    CacheService.set CacheService.KEYS.BROADCAST_FAILSAFE, true, {
      expireSeconds: FIVE_MINUTE_SECONDS
    }

  start: (messages, {isTestRun}) ->
    console.log 'broadcast start', messages[0].title

    (if isTestRun
      r.table 'users'
      .getAll 'austin', {index: 'username'}
      .map (doc) ->
        return doc('id')
    else
      r.table('users')
      .getAll(true, {index: 'hasPushToken'})
      .pluck(['id'])
    )
    .then (userIds) ->
      console.log 'sending to ', userIds.length
      userGroups = _.values _.chunk(userIds, AMOUNT_PER_BATCH)

      delay = 0
      _.map userGroups, (groupUserIds, i) ->
        KueCreateService.createJob
          job: {
            userIds: groupUserIds
            messages: messages
            percentage: i / userGroups.length
          }
          delaySeconds: delay
          type: KueCreateService.JOB_TYPES.BATCH_NOTIFICATION
        delay += TIME_PER_BATCH_SECONDS
      console.log 'batch done'

  batchNotify: ({userIds, messages, percentage}) ->
    console.log 'batch', userIds.length, percentage
    CacheService.get CacheService.KEYS.BROADCAST_FAILSAFE
    .then (failSafe) ->
      if failSafe
        console.log 'skipping (failsafe)'
      else
        Promise.map userIds, (userId) ->
          User.getById userId
          .then (user) ->
            Promise.each messages, (message) ->
              PushNotificationService.send user, message
              .catch (err) ->
                console.log 'push error', err
        .catch (err) ->
          console.log err
          console.log 'map error'

  broadcast: (messages, {isTestRun, uniqueId}) =>
    key = "#{CacheService.LOCK_PREFIXES.BROADCAST}:#{uniqueId}"
    console.log 'broadcast.broadcast', key
    if messages.allowRebroadcast
      @start messages, {isTestRun}
    else
      CacheService.runOnce key, =>
        @start messages, {isTestRun}

module.exports = new BroadcastService()
