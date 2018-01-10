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
Item = require '../models/item'
Product = require '../models/product'
SpecialOffer = require '../models/special_offer'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
GroupUser = require '../models/group_user'
Ban = require '../models/ban'
allItems = require '../resources/data/items'
allProducts = require '../resources/data/products'
allSpecialOffers = require '../resources/data/special_offers'
r = require './rethinkdb'
config = require '../config'

THIRTY_SECONDS = 30

class CronService
  constructor: ->
    @crons = []

    # minute
    # @addCron 'minute', '0 * * * * *', ->
    #   EventService.notifyForStart()
    #   if config.ENV is config.ENVS.PROD and not config.IS_STAGING
    #     CacheService.get CacheService.KEYS.AUTO_REFRESH_SUCCESS_COUNT
    #     .then (successCount) ->
    #       unless successCount
    #         console.log 'starting auto refresh'
    #         ClashRoyalePlayerService.updateAutoRefreshPlayers()
    #
    # @addCron 'quarterMinute', '15 * * * * *', ->
    #   CleanupService.clean()
    #   Thread.updateScores 'stale'
    #
    # # minute on 3/4 minute
    # @addCron 'threeQuarterMinute', '45 * * * * *', ->
    #   if config.ENV is config.ENVS.PROD
    #     ClashRoyalePlayerService.updateTopPlayers()
    #
    # @addCron 'tenMin', '0 */10 * * * *', ->
    #   VideoDiscoveryService.updateGroupVideos()
    #   Product.batchUpsert allProducts
    #   Item.batchUpsert allItems
    #   SpecialOffer.batchUpsert allSpecialOffers
    #   Thread.updateScores 'time'
    #
    # @addCron 'oneHour', '0 0 * * * *', ->
    #   CleanupService.trimLeaderboards()

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
