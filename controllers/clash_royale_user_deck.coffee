_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
UserData = require '../models/user_data'
Player = require '../models/player'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_USER_DECK.DECK
]

class ClashRoyaleUserDeckCtrl
  getFavoritedDeckIds: ({}, {user}) ->
    ClashRoyaleUserDeck.getAllFavoritedByUserId user.id
    .map ({deckId}) -> deckId

  getAllByUserId: ({userId, sort, filter}, {user}) ->
    Player.getByUserIdAndGameId userId, config.CLASH_ROYALE_ID
    .then EmbedService.embed {
      embed: [EmbedService.TYPES.PLAYER.VERIFIED_USER]
      gameId: config.CLASH_ROYALE_ID
    }
    .then (player) ->
      unless player
        router.throw {status: 404, info: 'player not found'}
      if player.data.mode is 'private' and user.id isnt player.verifiedUser?.id
        router.throw {status: 403, info: 'profile is private'}
      ClashRoyaleUserDeck.getAllByUserId userId, {sort}
      .map EmbedService.embed {embed: defaultEmbed}
      .map ClashRoyaleUserDeck.sanitize null

  getByDeckId: ({deckId}, {user}) ->
    ClashRoyaleUserDeck.getByDeckIdAndUserId deckId, user.id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleUserDeck.sanitize null

  # favorite: ({deckId}, {user}) ->
  #   ClashRoyaleUserDeck.upsertByDeckIdAndUserId deckId, user.id, {
  #     isFavorited: true
  #   }
  #   .tap ->
  #     ClashRoyaleUserDeck.processUpdate user.id
  #
  # unfavorite: ({deckId}, {user}) ->
  #   console.log 'abc', user.id
  #   ClashRoyaleUserDeck.upsertByDeckIdAndUserId deckId, user.id, {
  #     isFavorited: false
  #   }
  #   .tap ->
  #     ClashRoyaleUserDeck.processUpdate user.id
  #
  # create: ({cardIds, name, cardKeys}, {user}) ->
  #   ClashRoyaleDeck.getByCardKeys cardKeys
  #   .then (deck) ->
  #     if deck
  #       deck
  #     else
  #       ClashRoyaleDeck.create {
  #         cardIds, name, cardKeys, creatorId: user.id
  #       }
  #   .then (deck) ->
  #     ClashRoyaleUserDeck.upsertByDeckIdAndUserId deck.id, user.id, {
  #       name
  #       isFavorited: true
  #     }
  #     .tap ->
  #       ClashRoyaleUserDeck.processUpdate user.id

module.exports = new ClashRoyaleUserDeckCtrl()
