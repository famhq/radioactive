_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

knex = require '../services/knex'
cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'player_records_by_playerId'
    fields:
      playerId: 'text'
      gameRecordTypeId: 'uuid'
      value: 'int'
      scaledTime: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['playerId', 'gameRecordTypeId']
      clusteringColumns: ['scaledTime']
    withClusteringOrderBy: ['scaledTime', 'desc']
  }
]

defaultPlayerRecord = (playerRecord) ->
  unless playerRecord?
    return null

  _.defaults playerRecord, {
    time: new Date()
  }

PLAYER_RECORDS_TABLE = 'player_records'

class PlayerRecordModel
  SCYLLA_TABLES: tables

  batchUpsert: (playerRecords) ->
    if _.isEmpty playerRecords
      return Promise.resolve null
    cknex.batchRun _.map playerRecords, (playerRecord) ->
      playerRecord = defaultPlayerRecord playerRecord
      cknex().update 'player_records_by_playerId'
      .set _.omit playerRecord, ['playerId', 'gameRecordTypeId', 'scaledTime']
      .where 'playerId', '=', playerRecord.playerId
      .andWhere 'gameRecordTypeId', '=', playerRecord.gameRecordTypeId
      .andWhere 'scaledTime', '=', playerRecord.scaledTime

  getScaledTimeByTimeScale: (timeScale, time) ->
    time ?= moment()
    if timeScale is 'day'
      'DAY-' + time.format 'YYYY-MM-DD'
    else if timeScale is 'biweek'
      'BIWEEK-' + time.format('YYYY') + (parseInt(time.format 'YYYY-WW') / 2)
    else if timeScale is 'week'
      'WEEK-' + time.format 'YYYY-WW'
    else
      time.format time.format 'YYYY-MM-DD HH:mm'

  getRecord: ({gameRecordTypeId, playerId, scaledTime}) ->
    cknex().select '*'
    .from 'player_records_by_playerId'
    .where 'playerId', '=', playerId
    .andWhere 'gameRecordTypeId', '=', gameRecordTypeId
    .andWhere 'scaledTime', '=', scaledTime
    .run {isSingle: true}

  getRecords: (options) ->
    {gameRecordTypeId, playerId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    cknex().select '*'
    .from 'player_records_by_playerId'
    .where 'playerId', '=', playerId
    .where 'gameRecordTypeId', '=', gameRecordTypeId
    .where 'scaledTime', '>=', minScaledTime
    .where 'scaledTime', '<=', maxScaledTime
    .limit limit
    .run()

  upsert: (playerRecord) ->
    playerRecord = defaultPlayerRecord playerRecord
    cknex().update 'player_records_by_playerId'
    .set _.omit playerRecord, ['playerId', 'gameRecordTypeId', 'scaledTime']
    .where 'playerId', '=', playerRecord.playerId
    .andWhere 'gameRecordTypeId', '=', playerRecord.gameRecordTypeId
    .andWhere 'scaledTime', '=', playerRecord.scaledTime

  migrateUserRecords: (playerId) ->
    knex.select().table 'user_records'
    .where {playerId}
    .distinct(knex.raw('ON ("scaledTime") *'))
    .map (record) ->
      delete record.id
      delete record.userId
      _.defaults {
        playerId: playerId
      }, record
    .then (records) =>
      @batchCreate records
      .catch (err) ->
        null
        # console.log 'migrate records err', playerId

module.exports = new PlayerRecordModel()
