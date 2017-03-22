_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS
  EmbedService.TYPES.CLASH_ROYALE_DECK.POPULARITY
]

class ClashRoyaleDeckCtrl
  getAll: ({sort, filter}, {user}) ->
    if filter is 'mine'
      decks = ClashRoyaleUserDeck.getAllFavoritedByUserId user.id
      .map EmbedService.embed {
        embed: [EmbedService.TYPES.CLASH_ROYALE_USER_DECK.DECK]
      }
      .map ({deck}) -> deck
      .then (decks) ->
        _.uniqBy _.filter(decks), 'id'
    else
      decks = ClashRoyaleDeck.getAll({sort})

    decks
    .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleDeck.sanitize null

  getById: ({id}, {user}) ->
    ClashRoyaleDeck.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleDeck.sanitize null

module.exports = new ClashRoyaleDeckCtrl()
