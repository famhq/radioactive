_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
UserData = require '../models/user_data'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS
  EmbedService.TYPES.CLASH_ROYALE_DECK.POPULARITY
]

class ClashRoyaleDeckCtrl
  getAll: ({sort, filter}, {user}) ->
    if filter is 'mine'
      decks = UserData.getByUserId user.id
      .then (userData) ->
        ClashRoyaleDeck.getByIds userData.clashRoyaleDeckIds
    else
      decks = ClashRoyaleDeck.getAll({sort})

    decks
    .map EmbedService.embed defaultEmbed
    .map ClashRoyaleDeck.sanitize null

  getById: ({id}, {user}) ->
    ClashRoyaleDeck.getById id
    .then EmbedService.embed defaultEmbed
    .then ClashRoyaleDeck.sanitize null

  favorite: ({id}, {user}) ->
    UserData.getByUserId user.id
    .then (userData) ->
      UserData.upsertByUserId user.id, {
        clashRoyaleDeckIds: _.uniq userData.clashRoyaleDeckIds.concat [id]
      }

  unfavorite: ({id}, {user}) ->
    UserData.getByUserId user.id
    .then (userData) ->
      UserData.upsertByUserId user.id, {
        clashRoyaleDeckIds: _.filter userData.clashRoyaleDeckIds, (deckId) ->
          deckId isnt id
      }

module.exports = new ClashRoyaleDeckCtrl()
