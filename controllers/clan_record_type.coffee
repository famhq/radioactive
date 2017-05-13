_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

ClanRecordType = require '../models/game_record_type'
Clan = require '../models/clan'
EmbedService = require '../services/embed'
config = require '../config'

allowedClientEmbeds = ['clanValues']

class ClanRecordTypeCtrl

  getAllByClanIdAndGameId: ({clanId, gameId, embed}, {user}) ->
    embed ?= []
    embed = _.filter embed, (item) ->
      allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.CLAN_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

    # ClanRecordType.getAllByGameId gameId
    Promise.resolve([
      {
        id: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        name: 'Trophies'
        timeScale: 'weeks'
        gameId: config.CLASH_ROYALE_ID
      }
      {
        id: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        name: 'Donations'
        timeScale: 'weeks'
        gameId: config.CLASH_ROYALE_ID
      }
    ])
    .map EmbedService.embed {embed, clanId}

module.exports = new ClanRecordTypeCtrl()
