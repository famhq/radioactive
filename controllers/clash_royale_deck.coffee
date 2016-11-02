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
      .then EmbedService.embed [
        EmbedService.TYPES.USER_DATA.CLASH_ROYALE_DECK_IDS
      ]
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

module.exports = new ClashRoyaleDeckCtrl()
