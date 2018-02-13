_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

CacheService = require '../services/cache' # FIXME rm

ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
GameRecordType = require '../models/game_record_type'
User = require '../models/user'
EmbedService = require '../services/embed'
config = require '../config'

allowedClientEmbeds = ['meValues']

class GameRecordTypeCtrl

  getAllByPlayerIdAndGameKey: ({playerId, gameKey, embed}, {user}) ->
    unless playerId
      return
    embed ?= []
    embed = _.filter embed, (item) ->
      allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.GAME_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

    # GameRecordType.getAllByGameId gameKey
    Promise.resolve([
      {
        id: config.CLASH_ROYALE_TROPHIES_RECORD_ID
        name: 'Trophies'
        timeScale: 'minutes'
        gameKey: 'clash-royale'
      }
      {
        id: config.CLASH_ROYALE_DONATIONS_RECORD_ID
        name: 'Donations'
        timeScale: 'weeks'
        gameKey: 'clash-royale'
      }
      {
        id: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
        name: 'Clan chest crowns'
        timeScale: 'weeks'
        gameKey: 'clash-royale'
      }
    ])
    .map EmbedService.embed {embed, playerId}

module.exports = new GameRecordTypeCtrl()
