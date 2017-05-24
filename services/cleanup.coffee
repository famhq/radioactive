Promise = require 'bluebird'
moment = require 'moment'

r = require './rethinkdb'
knex = require './knex'
KueCreateService = require './kue_create'
config = require '../config'

ONE_WEEK_MS = 3600 * 24 * 7 * 1000
FOUR_WEEKS_MS = 3600 * 24 * 28 * 1000
MIN_KUE_STUCK_TIME_MS = 60 * 10 * 1000 # 10 minutes

class CleanupService
  clean: =>
    console.log 'cleaning...'
    start = Date.now()
    Promise.all [
      @cleanUserRecords()
      @cleanClashRoyaleMatches()
      @cleanKue()
    ]
    .then ->
      console.log 'clean done', Date.now() - start

  cleanKue: ->
    KueCreateService.clean {
      types: ['active', 'failed'], minStuckTimeMs: MIN_KUE_STUCK_TIME_MS
    }

  cleanClashRoyaleMatches: ->
    knex.table 'matches'
    .where 'time', '<', moment().subtract(ONE_WEEK_MS).toDate()
    .delete()

  cleanUserRecords: ->
    knex.table 'user_records'
    .where 'time', '<', moment().subtract(FOUR_WEEKS_MS).toDate()
    .delete()

module.exports = new CleanupService()
