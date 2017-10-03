_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS
  EmbedService.TYPES.CLASH_ROYALE_DECK.POPULARITY
]

class ClashRoyaleDeckCtrl
  getAll: ({sort, filter}, {user}) ->
    if filter is 'mine'
      decks =
        Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
        .then (player) ->
          ClashRoyalePlayerDeck.getAllByPlayerId player.id
          .map EmbedService.embed {
            embed: [EmbedService.TYPES.CLASH_ROYALE_PLAYER_DECK.DECK]
          }
          .map ({deck}) -> deck
          .then (decks) ->
            _.uniqBy _.filter(decks), 'id'
    # else # TODO
    #   decks = ClashRoyaleDeck.getAll({sort})

    decks
    .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleDeck.sanitize null

  getById: ({id}, {user}) ->
    ClashRoyaleDeck.getById decodeURIComponent id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleDeck.sanitize null

module.exports = new ClashRoyaleDeckCtrl()
