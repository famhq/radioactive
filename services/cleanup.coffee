Promise = require 'bluebird'

r = require './rethinkdb'
KueCreateService = require './kue_create'
config = require '../config'

MIN_KUE_STUCK_TIME_MS = 500 # 60 * 10 * 1000 # 10 minutes

class CleanupService
  clean: =>
    console.log 'cleaning...'
    start = Date.now()
    Promise.all [
      # @cleanGameRecords()
      # @cleanClashRoyaleMatches
      @cleanKue()
    ]
    .then ->
      console.log 'clean done', Date.now() - start

  cleanKue: ->
    KueCreateService.clean {
      types: ['active', 'failed'], minStuckTimeMs: MIN_KUE_STUCK_TIME_MS
    }

  cleanClashRoyaleMatches: +
    r.db('radioactive').table('clash_royale_matches')
    .between(0, r.now().sub(3600 * 24 * 14), {index: 'time'})
    .limit(100).delete({durability: 'soft'})
    .run()

  cleanGameRecords: ->
    r.db('radioactive').table('game_records')
    .between(
      ['0', 0]
      ['z', r.now().sub(3600 * 24 * 7)]
      {index: 'gameRecordTypeTime'}
    )
    .limit(500).delete({durability: 'soft'})
    .run()

module.exports = new CleanupService()
