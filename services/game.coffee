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
    gameKey ?= 'clash-royale'
    unless @Games[gameKey]
      console.log 'missing', gameKey
    @Games[gameKey].updatePlayerByPlayerId playerId, options

  getPlayerDataByPlayerIdAndGameKey: (playerId, gameKey, options) =>
    gameKey ?= 'clash-royale'
    unless @Games[gameKey]
      console.log 'missing', gameKey
    @Games[gameKey].getPlayerDataByPlayerId playerId, options

  formatByPlayerIdAndGameKey: (playerId, gameKey) =>
    gameKey ?= 'clash-royale'
    unless @Games[gameKey]
      console.log 'missing', gameKey
    @Games[gameKey].formatByPlayerId playerId

  isValidByPlayerIdAndGameKey: (playerId, gameKey) =>
    gameKey ?= 'clash-royale'
    unless @Games[gameKey]
      console.log 'missing', gameKey
    @Games[gameKey].isValidByPlayerId playerId


module.exports = new GameService()
