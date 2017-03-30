_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
cards = require '../resources/data/cards'
Card = require '../models/clash_royale_card'
Match = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'

r.db('radioactive').table('clash_royale_decks')
.filter(r.row('cardIds').count().eq(0))
.limit 20000
.run()
.then (decks) ->
  i = 0
  Promise.map decks, (deck, i) ->
    i += 1
    console.log i
    cardKeys = deck.cardKeys.split '|'
    Promise.all _.map cardKeys, (key) -> Card.getByKey key, {preferCache: true}
    .then (cards) ->
      Deck.updateById deck.id, {
        cardIds: _.filter _.map cards, 'id'
      }
  , {concurrency: 10}
.then ->
  console.log 'done'
