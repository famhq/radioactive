CronJob = require('cron').CronJob
_ = require 'lodash'
Promise = require 'bluebird'

CacheService = require './cache'
KueCreateService = require './kue_create'
ClashTvService = require './clash_tv'
VideoDiscoveryService = require './video_discovery'
EventService = require './event'
ClashRoyaleApiService = require './clash_royale_api'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
r = require './rethinkdb'
config = require '../config'

THIRTY_SECONDS = 30

class CronService
  constructor: ->
    @crons = []

    # minute
    @addCron 'minute', '0 * * * * *', ->
      EventService.notifyForStart()
      # ClashApiSiuervice.process()
      # get all game_users where lastUpdate > 12 hours
      # get all clans where lastUpdate > 12 hours
      # have a check to make sure update doesn't take longer than a minuteS

    @addCron 'hourly', '0 0 * * * *', ->
      VideoDiscoveryService.discover()

    @addCron 'halfHourly', ' 0 12,42 * * * *', ->
      ClashRoyaleApiService.process()

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
