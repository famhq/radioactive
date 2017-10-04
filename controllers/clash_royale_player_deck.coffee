_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Player = require '../models/player'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_PLAYER_DECK.DECK
]

class ClashRoyalePlayerDeckCtrl
  getAllByPlayerId: ({playerId, sort, type}, {user}) ->
    Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
    .then EmbedService.embed {
      embed: [EmbedService.TYPES.PLAYER.VERIFIED_USER]
      gameId: config.CLASH_ROYALE_ID
    }
    .then (player) ->
      unless player
        router.throw {status: 404, info: 'player not found'}
      if player.data.mode is 'private' and
          user.id isnt player.verifiedUser?.id and
          playerId is player.id
        router.throw {status: 403, info: 'profile is private'}

      # TODO: rm ~early nov
      key = "pdmigrate16:#{player.id}"
      CacheService.runOnce key, ->
        if user.joinTime?.getTime() < 1507108006320 # oct 3
          ClashRoyalePlayerDeck.migrate player.id
      .then ->
        ClashRoyalePlayerDeck.getAllByPlayerId playerId, {sort, type}
      .map EmbedService.embed {embed: defaultEmbed}
      .map ClashRoyalePlayerDeck.sanitize null

  getByDeckId: ({deckId}, {user}) ->
    Player.getByUserIdAndGameId userId, config.CLASH_ROYALE_ID
    .then (player) ->
      unless player
        router.throw {status: 404, info: 'player not found'}
      ClashRoyalePlayerDeck.getByDeckIdAndPlayerId deckId, player.id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyalePlayerDeck.sanitize null

module.exports = new ClashRoyalePlayerDeckCtrl()
