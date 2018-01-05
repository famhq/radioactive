Promise = require 'bluebird'
moment = require 'moment'

r = require './rethinkdb'
KueCreateService = require './kue_create'
CacheService = require './cache'
config = require '../config'

ONE_WEEK_MS = 3600 * 24 * 7 * 1000
FOUR_WEEKS_MS = 3600 * 24 * 28 * 1000
TWO_MIN_MS = 60 * 2 * 1000
MIN_KUE_STUCK_TIME_MS = 60 * 10 * 1000 # 10 minutes

TRIMMABLE_LEADERBOARDS = [
  {
    key: CacheService.STATIC_PREFIXES.GAME_TYPE_DECK_LEADERBOARD
    trimLength: 10000
  }
  {
    key: CacheService.STATIC_PREFIXES.CARD_DECK_LEADERBOARD
    trimLength: 10000
  }
]

class CleanupService
  clean: =>
    console.log 'cleaning...'
    start = Date.now()
    Promise.all [
      # @cleanPlayerRecords()
      # @cleanClashRoyaleMatches()
      # @cleanPlayerDecks()
      @cleanKue()
    ]
    .then ->
      console.log 'clean done', Date.now() - start

  cleanKue: ->
    KueCreateService.clean {
      types: ['active', 'failed'], minStuckTimeMs: MIN_KUE_STUCK_TIME_MS
    }

  trimLeaderboards: ->
    Promise.each TRIMMABLE_LEADERBOARDS, ({key, trimLength}) ->
      CacheService.leaderboardTrim key, trimLength

module.exports = new CleanupService()
