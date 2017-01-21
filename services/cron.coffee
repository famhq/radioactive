CronJob = require('cron').CronJob
_ = require 'lodash'
Promise = require 'bluebird'

CacheService = require './cache'
KueCreateService = require './kue_create'
ClashTvService = require './clash_tv'
EventService = require './event'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
r = require './rethinkdb'
config = require '../config'

THIRTY_SECONDS = 30

class CronService
  constructor: ->
    @crons = []

    # midnight
    @addCron 'daily', '0 0 0 * * *', ->
      r.table('user_daily_data').delete()

    # minute
    @addCron 'minute', '0 * * * * *', ->
      EventService.notifyForStart()

    # @addCron 'hourly', '0 0 * * * *', ->
    #   ClashTvService.process()

    # daily 6pm PT
    # @addCron 'winRates', '0 0 2 * * *', ->
    #   Promise.all [
    #     ClashRoyaleDeck.updateWinsAndLosses()
    #     ClashRoyaleCard.updateWinsAndLosses()
    #   ]

  addCron: (key, time, fn) =>
    @crons.push new CronJob {
      cronTime: time
      onTick: ->
        CacheService.runOnce(key, fn, {
          # if server times get offset by >= 30 seconds, crons get run twice...
          # so this is not guaranteed to run just once
          expireSeconds: THIRTY_SECONDS
        })
      start: false
      timeZone: 'America/Los_Angeles'
    }

  start: =>
    _.map @crons, (cron) ->
      cron.start()

module.exports = new CronService()
