_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

ClanRecordType = require '../models/game_record_type'
Clan = require '../models/clan'
EmbedService = require '../services/embed'
config = require '../config'

allowedClientEmbeds = ['clanValues']

class ClanRecordTypeCtrl

  getAllByClanIdAndGameKey: ({clanId, gameKey, embed}, {user}) ->
    embed ?= []
    embed = _.filter embed, (item) ->
      allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.CLAN_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

    # ClanRecordType.getAllByGameId gameKey
    Promise.resolve([
      {
        id: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        name: 'Trophies'
        timeScale: 'weeks'
        gameKey: 'clash-royale'
      }
      {
        id: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        name: 'Donations'
        timeScale: 'weeks'
        gameKey: 'clash-royale'
      }
    ])
    .map EmbedService.embed {embed, clanId}

module.exports = new ClanRecordTypeCtrl()
