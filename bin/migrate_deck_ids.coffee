#!/usr/bin/env coffee
_ = require 'lodash'
Promise = require 'bluebird'
Deck = require '../models/clash_royale_deck'
r = require '../services/rethinkdb'


r.db('radioactive').table('user_data')
.filter r.row('isNewId').default(false).eq(false)
.limit 15000
.run()
.then (userDatas) ->
  Promise.map userDatas, (userData, i) ->
    console.log i
    newId = userData.userId
    r.db('radioactive').table('user_data')
    .insert _.defaults {id: newId, isNewId: true}, _.clone userData
    .run()
    .then ->
      r.db('radioactive').table('user_data')
      .get userData.id
      .delete()
      .run()
    .catch ->
      console.log 'insert err'
  , {concurrency: 50}
.then ->
  console.log 'done'
return

# r.db('radioactive').table('players')
# .indexCreate('isNewId', function(row) {return row.hasFields('isNewId').not()})

# r.db('radioactive').table('clans')
# .filter r.row('code').default(null).eq(null)
# .pluck ['id']
# .limit 5000
# .run()
# .then (clans) ->
#   console.log 'got', clans.length
#   Promise.map clans, (clan, i) ->
#     console.log i
#     r.db('radioactive').table('clans').get(clan.id)
#     .update {
#       code: _.sampleSize('ABCDEFGHIJKLMNOPQRSTUFWXYZ1234567890', 6).join ''
#     }
#     .run()
#   , {concurrency: 100}
# .then ->
#   console.log 'done'
return

r.db('radioactive').table('clash_royale_decks')
.getAll true, {index: 'isNewId'}
.limit 2000
.run()
.then (decks) ->
  Promise.map decks, (deck, i) ->
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

return
r.db('radioactive').table('clash_royale_user_decks')
# .getAll true, {index: 'isNewId'}
.filter(r.row('isNewId').default(null).eq(null))
.limit 2000
.run()
.then (userDecks) ->
  Promise.map userDecks, (userDeck, i) ->
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






###


# r.db('radioactive').table('clash_royale_decks')
# .getAll true, {index: 'isNewId'}
# .limit 2000
# .run()
# .then (decks) ->
#   Promise.map decks, (deck, i) ->
#     console.log 'lll', i
#     newDeckId = deck.cardKeys
#     console.log deck.id, newDeckId
#     r.db('radioactive').table('clash_royale_decks')
#     .insert _.defaults {id: newDeckId, oldId: deck.id, isNewId: true}, _.clone deck
#     .run()
#     .catch ->
#       console.log 'insert err'
#
#     r.db('radioactive').table('clash_royale_user_decks')
#     .getAll deck.id, {index: 'deckId'}
#     .update {deckId: newDeckId}
#     .run()
#
#     r.db('radioactive').table('clash_royale_decks').get(deck.id)
#     .delete()
#     .run()
#   , {concurrency: 100}

# r.db('radioactive').table('clash_royale_user_decks')
# .getAll true, {index: 'isNewId'}
# # .filter(r.row('isNewId').default(null).eq(null))
# .limit 3000
# .run()
# .then (userDecks) ->
#   Promise.map userDecks, (userDeck, i) ->
#     if userDeck.userId
#       newUserDeckId = "#{userDeck.userId}:#{userDeck.deckId}"
#       r.db('radioactive').table('clash_royale_user_decks')
#       .insert _.defaults {id: newUserDeckId, oldId: userDeck.id, isNewId: true}, _.clone userDeck
#       .run()
#       .catch ->
#         console.log 'insert err'
#
#       r.db('radioactive').table('clash_royale_user_decks').get(userDeck.id)
#       .delete()
#       .run()
#     else
#       r.db('radioactive').table('clash_royale_user_decks').get(userDeck.id)
#       .delete()
#       .run()
#   , {concurrency: 100}
###



















# r = require '../services/rethinkdb'
# r.db('radioactive').table('threads').run()
# .then (threads) ->
#   Promise.map threads, (thread) ->
#     Deck.getById thread.data?.deckId
#     .then (deck) ->
#       if deck?.cardKeys
#         r.db('radioactive').table('threads').get(thread.id).update {
#           data: {deckId: deck.cardKeys}
#         }
#   , {concurrency: 10}
# .then ->
#   console.log 'done'
# r.db('radioactive').table('clash_royale_decks')
# .filter(r.row('isNewId').default(null).eq(null))
# .limit 1000
# .run()
# .then (decks) ->
#   Promise.map decks, (deck, i) ->
#     console.log i
#     newDeckId = deck.cardKeys
#     Promise.all [
#       r.db('radioactive').table('clash_royale_decks')
#       .insert _.defaults {id: newDeckId, oldDeckId: deck.id, isNewId: true}, _.clone(deck)
#       .run()
#
#       r.db('radioactive').table('clash_royale_decks')
#       .get deck.id
#       .delete()
#       .run()
#
#       r.db('radioactive').table('clash_royale_user_decks')
#       .getAll(deck.id, {index: 'deckId'})
#       .update {deckId: newDeckId}
#       .run()
#     ]
#   , {concurrency: 50}
# .then ->
#   console.log 'done'
