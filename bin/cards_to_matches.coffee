_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
cards = require '../resources/data/cards'
Card = require '../models/clash_royale_card'
Match = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'

r.table 'clash_royale_matches'
.filter r.row('cardIds').default(null).eq(null)
.run()
.then (matches) ->
  Promise.map matches, (match, i) ->
    console.log i / matches.length
    Promise.all [
      Deck.getById match.deck1Id
      Deck.getById match.deck2Id
    ]
    .then ([deck1, deck2]) ->
      if deck1 and deck2
        Match.updateById match.id, {
          deck1CardIds: deck1.cardIds
          deck2CardIds: deck2.cardIds
        }
      else
        Match.deleteById match.id
  , {concurrency: 10}
