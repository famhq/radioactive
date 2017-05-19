_ = require 'lodash'
Promise = require 'bluebird'

r = require './rethinkdb'
User = require '../models/user'
CacheService = require './cache'
KueCreateService = require './kue_create'
PushNotificationService = require './push_notification'
config = require '../config'

AMOUNT_PER_BATCH = 500
TIME_PER_BATCH_SECONDS = 5
FIVE_MINUTE_SECONDS = 5 * 60

class BroadcastService
  failSafe: ->
    CacheService.set CacheService.KEYS.BROADCAST_FAILSAFE, true, {
      expireSeconds: FIVE_MINUTE_SECONDS
    }

  start: (message, {isTestRun}) ->
    console.log 'broadcast start', message.title

    (if isTestRun
      r.table 'users'
      .getAll 'austin', {index: 'username'}
      .map (doc) ->
        return doc('id')
    else
      r.table('users')
      .getAll(true, {index: 'hasPushToken'})
      .skip 50000
      .limit 50000
      .pluck(['id'])
      .map (doc) ->
        return doc('id')
    )
    .then (userIds) ->
      console.log 'sending to ', userIds.length
      userGroups = _.values _.chunk(userIds, AMOUNT_PER_BATCH)

      delay = 0
      _.map userGroups, (groupUserIds, i) ->
        KueCreateService.createJob
          job: {
            userIds: groupUserIds
            message: message
            percentage: i / userGroups.length
          }
          delaySeconds: delay
          type: KueCreateService.JOB_TYPES.BATCH_NOTIFICATION
        delay += TIME_PER_BATCH_SECONDS
      console.log 'batch done'

  batchNotify: ({userIds, message, percentage}) ->
    console.log 'batch', userIds.length, percentage
    CacheService.get CacheService.KEYS.BROADCAST_FAILSAFE
    .then (failSafe) ->
      if failSafe
        console.log 'skipping (failsafe)'
      else
        Promise.map userIds, (userId) ->
          User.getById userId
          .then (user) ->
            langCode = if user.country in [
              'AR', 'BO', 'CR', 'CU', 'DM', 'EC',
              'SV', 'GQ', 'GT', 'HN', 'MX'
              'NI', 'PA', 'PE', 'ES', 'UY', 'VE'
            ]
            then 'es'
            else 'en'
            lang = message.lang[langCode] or message.lang['en']
            message = _.defaults {
              title: lang.title
              text: lang.text
            }, _.clone(message)
            PushNotificationService.send user, message
            .catch (err) ->
              console.log 'push error', err
        .catch (err) ->
          console.log err
          console.log 'map error'

  broadcast: (message, {isTestRun, uniqueId}) =>
    key = "#{CacheService.LOCK_PREFIXES.BROADCAST}:#{uniqueId}"
    console.log 'broadcast.broadcast', key
    if message.allowRebroadcast
      @start message, {isTestRun}
    else
      CacheService.runOnce key, =>
        @start message, {isTestRun}

module.exports = new BroadcastService()
