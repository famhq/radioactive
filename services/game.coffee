_ = require 'lodash'
Promise = require 'bluebird'

ClashRoyaleService = require './game_clash_royale'
FortniteGameService = require './game_fortnite'
config = require '../config'

class GameService
  constructor: ->
    @Games =
      'clash-royale': ClashRoyaleService
      fortnite: FortniteGameService

  updatePlayerByPlayerIdAndGameKey: (playerId, gameKey, options) =>
    @Games[gameKey].updatePlayerByPlayerId playerId, options

  getPlayerDataByPlayerIdAndGameKey: (playerId, gameKey, options) =>
    @Games[gameKey].getPlayerDataByPlayerId playerId, options

  formatByPlayerIdAndGameKey: (playerId, gameKey) =>
    @Games[gameKey].formatByPlayerId playerId

  isValidByPlayerIdAndGameKey: (playerId, gameKey) =>
    @Games[gameKey].isValidByPlayerId playerId


module.exports = new GameService()
