CronJob = require('cron').CronJob
_ = require 'lodash'
Promise = require 'bluebird'

CacheService = require './cache'
KueCreateService = require './kue_create'
VideoDiscoveryService = require './video_discovery'
EventService = require './event'
ClashRoyalePlayerService = require './clash_royale_player'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
r = require './rethinkdb'
config = require '../config'

THIRTY_SECONDS = 30

# ClashRoyalePlayerService.process()

class CronService
  constructor: ->
    @crons = []

    # minute
    @addCron 'minute', '0 * * * * *', ->
      EventService.notifyForStart()
      ClashRoyalePlayerService.updateStalePlayerData()
      ClashRoyalePlayerService.updateStalePlayerMatches()

      r.db('radioactive').table('clash_royale_decks')
      .getAll true, {index: 'isNewId'}
      .limit 500
      .run()
      .then (decks) ->
        Promise.map decks, (deck, i) ->
          console.log 'lll', i
          newDeckId = deck.cardKeys
          console.log deck.id, newDeckId
          r.db('radioactive').table('clash_royale_decks')
          .insert _.defaults {id: newDeckId, oldId: deck.id, isNewId: true}, _.clone deck
          .run()
          .catch ->
            console.log 'insert err'

          r.db('radioactive').table('clash_royale_user_decks')
          .getAll deck.id, {index: 'deckId'}
          .update {deckId: newDeckId}
          .run()

          r.db('radioactive').table('clash_royale_decks').get(deck.id)
          .delete()
          .run()
        , {concurrency: 100}

      r.db('radioactive').table('clash_royale_user_decks')
      # .getAll true, {index: 'isNewId'}
      .filter(r.row('isNewId').default(null).eq(null))
      .limit 3000
      .run()
      .then (userDecks) ->
        Promise.map userDecks, (userDeck, i) ->
          console.log 'ppp', i
          if userDeck.userId
            newUserDeckId = "#{userDeck.userId}:#{userDeck.deckId}"
            r.db('radioactive').table('clash_royale_user_decks')
            .insert _.defaults {id: newUserDeckId, oldId: userDeck.id, isNewId: true}, _.clone userDeck
            .run()
            .catch ->
              console.log 'insert err'

            r.db('radioactive').table('clash_royale_user_decks').get(userDeck.id)
            .delete()
            .run()
          else
            r.db('radioactive').table('clash_royale_user_decks').get(userDeck.id)
            .update {isNewId: true}
            .run()
        , {concurrency: 100}

    # minute on half minute
    @addCron 'halfMinute', '30 * * * * *', ->
      ClashRoyaleUserDeck.processIncrementByDeckIdAndPlayerId()
      ClashRoyaleDeck.processIncrementById()

    # minute on 3/4 minute
    @addCron 'threeQuarterMinute', '45 * * * * *', ->
      ClashRoyalePlayerService.updateTopPlayers()

    @addCron 'hourly', '0 0 * * * *', ->
      VideoDiscoveryService.discover()

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
