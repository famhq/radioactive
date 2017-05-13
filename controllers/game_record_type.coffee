_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

knex = require '../services/knex' # FIXME rm
CacheService = require '../services/cache' # FIXME rm
UserRecord = require '../models/user_record'

GameRecordType = require '../models/game_record_type'
User = require '../models/user'
EmbedService = require '../services/embed'
config = require '../config'

allowedClientEmbeds = ['meValues']

class GameRecordTypeCtrl

  getAllByUserIdAndGameId: ({userId, gameId, embed}, {user}) ->
    unless userId
      return
    embed ?= []
    embed = _.filter embed, (item) ->
      allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.GAME_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

    # FIXME FIXME: rm whenever (migration)
    key = CacheService.PREFIXES.USER_RECORDS_MIGRATE + ':' + userId
    CacheService.runOnce key, ->
      knex.select().table 'user_records_old'
      .where {userId}
      .distinct(knex.raw('ON ("userId", "gameRecordTypeId", "scaledTime") *'))
      .then (records) ->
        records = _.map records, (record) ->
          delete record.id
          record
        UserRecord.batchCreate records
    .then ->



      GameRecordType.getAllByGameId gameId
      Promise.resolve([
        {
          id: config.CLASH_ROYALE_TROPHIES_RECORD_ID
          name: 'Trophies'
          timeScale: 'minutes'
          gameId: config.CLASH_ROYALE_ID
        }
        {
          id: config.CLASH_ROYALE_DONATIONS_RECORD_ID
          name: 'Donations'
          timeScale: 'weeks'
          gameId: config.CLASH_ROYALE_ID
        }
        {
          id: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
          name: 'Clan chest crowns'
          timeScale: 'weeks'
          gameId: config.CLASH_ROYALE_ID
        }
      ])
      .map EmbedService.embed {embed, userId}

module.exports = new GameRecordTypeCtrl()
