CronJob = require('cron').CronJob
_ = require 'lodash'
Promise = require 'bluebird'

CacheService = require './cache'
VideoDiscoveryService = require './video_discovery'
EventService = require './event'
CleanupService = require './cleanup'
ClashRoyalePlayerService = require './clash_royale_player'
ClashRoyaleClanService = require './clash_royale_clan'
Thread = require '../models/thread'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
Ban = require '../models/ban'
r = require './rethinkdb'
config = require '../config'

THIRTY_SECONDS = 30
Thread.updateScores()
class CronService
  constructor: ->
    @crons = []

    # minute
    @addCron 'minute', '0 * * * * *', ->
      EventService.notifyForStart()
      if config.ENV is config.ENVS.PROD
        ClashRoyalePlayerService.updateStalePlayerData()
        ClashRoyalePlayerService.updateStalePlayerMatches()
        ClashRoyaleClanService.updateStale()

    @addCron 'quarterMinute', '15 * * * * *', ->
      CleanupService.clean()
      Thread.updateScores()

    # minute on half minute
    # @addCron 'halfMinute', '30 * * * * *', ->
      # ClashRoyaleUserDeck.processIncrementByDeckIdAndPlayerId()
      # ClashRoyaleDeck.processIncrementById()

    # minute on 3/4 minute
    @addCron 'threeQuarterMinute', '45 * * * * *', ->
      CleanupService.clean()
      if config.ENV is config.ENVS.PROD
        ClashRoyalePlayerService.updateTopPlayers()

    @addCron 'hourly', '0 0 * * * *', ->
      VideoDiscoveryService.discover()
      Ban.unbanTemp()

    # @addCron 'halfHourly', ' 0 0,30 * * * *', ->
    #   null

    # daily 6pm PT
    @addCron 'winRates', '0 0 2 * * *', ->
      Promise.all [
        ClashRoyaleDeck.updateWinsAndLosses()
        # ClashRoyaleCard.updateWinsAndLosses()
      ]

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
