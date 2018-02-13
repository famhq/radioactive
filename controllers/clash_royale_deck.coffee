_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS
  EmbedService.TYPES.CLASH_ROYALE_DECK.POPULARITY
]

TEN_MINUTES_SECONDS = 60 * 10

class ClashRoyaleDeckCtrl
  getAll: ({sort, filter}, {user}) ->
    if filter is 'mine'
      decks =
        Player.getByUserIdAndGameKey user.id, 'clash-royale'
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

  getPopular: ({gameType}) ->
    get = ->
      ClashRoyaleDeck.getPopularByGameType gameType, {limit: 200}
      .map EmbedService.embed {
        embed: [
          EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS
          EmbedService.TYPES.CLASH_ROYALE_DECK.STATS
        ]
      }
      # .map ClashRoyaleDeck.sanitize null
      .then (decks) ->
        decks = _.filter decks, (deck) ->
          deck.matchCount > 40 and _.find deck.stats, {gameType}
        decks = _.orderBy decks, (deck) ->
          challengeStats = _.find deck.stats, {gameType}
          challengeStats.winRate
        , 'desc'
        _.take decks, 50

    prefix = CacheService.PREFIXES.CLASH_ROYALE_DECK_GET_POPULAR
    cacheKey = "#{prefix}:#{gameType}"
    CacheService.preferCache cacheKey, get, {
      expireSeconds: TEN_MINUTES_SECONDS
    }

module.exports = new ClashRoyaleDeckCtrl()
