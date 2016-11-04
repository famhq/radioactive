_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
UserData = require '../models/user_data'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_USER_DECK.DECK
]

class ClashRoyaleUserDeckCtrl
  getAll: ({sort, filter}, {user}) ->
    ClashRoyaleUserDeck.getAllByUserId user.id
    .map EmbedService.embed defaultEmbed
    .map ClashRoyaleUserDeck.sanitize null

  getByDeckId: ({deckId}, {user}) ->
    ClashRoyaleUserDeck.getByDeckIdAndUserId deckId, user.id
    .then EmbedService.embed defaultEmbed
    .then ClashRoyaleUserDeck.sanitize null

  incrementByDeckId: ({deckId, state}, {user}) ->
    Promise.all [
      ClashRoyaleUserDeck.incrementByDeckIdAndUserId deckId, user.id, state
      ClashRoyaleDeck.incrementById deckId, state
    ]

  favorite: ({deckId}, {user}) ->
    ClashRoyaleUserDeck.upsertByDeckIdAndUserId deckId, user.id, {
      isFavorited: true
    }
    .tap ->
      ClashRoyaleUserDeck.processUpdate user.id

  unfavorite: ({deckId}, {user}) ->
    ClashRoyaleUserDeck.upsertByDeckIdAndUserId deckId, user.id, {
      isFavorited: false
    }
    .tap ->
      ClashRoyaleUserDeck.processUpdate user.id

  create: ({cardIds, name, cardKeys}, {user}) ->
    ClashRoyaleDeck.getByCardKeys cardKeys
    .then (deck) ->
      if deck
        deck
      else
        ClashRoyaleDeck.create {
          cardIds, name, cardKeys, createdByUserId: user.id
        }
    .then (deck) ->
      ClashRoyaleUserDeck.upsertByDeckIdAndUserId deck.id, user.id, {
        name
        isFavorited: true
      }
      .tap ->
        ClashRoyaleUserDeck.processUpdate user.id

module.exports = new ClashRoyaleUserDeckCtrl()
