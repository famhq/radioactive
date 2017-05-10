_ = require 'lodash'

ClashRoyalePlayerDaily = require './clash_royale_player_daily'
PlayerBase = require './player_base'
config = require '../config'

class PlayerDailyModel extends PlayerBase
  constructor: ->
    @GamePlayers =
      "#{config.CLASH_ROYALE_ID}": ClashRoyalePlayerDaily

module.exports = new PlayerDailyModel()
