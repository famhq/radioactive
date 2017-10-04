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

  batchUpsertByMatches: (matches) =>
    records = _.filter _.flatten _.map matches, (match) =>
      if match.type is 'PvP'
        scaledTime = @getScaledTimeByTimeScale(
          'minute', moment(match.time)
        )
        players = match.data.team.concat match.data.opponent
        _.map players, (player, i) ->
          value = player.startingTrophies + player.trophyChange
          if isNaN value
            return
          {
            playerId: player.tag.replace '#', ''
            gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
            scaledTime
            value: value
          }

    if _.isEmpty records
      return Promise.resolve null

    cknex.batchRun _.map records, (record) =>
      @upsert record, {skipRun: true}

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

  upsert: (playerRecord, {skipRun} = {}) ->
    playerRecord = defaultPlayerRecord playerRecord
    q = cknex().update 'player_records_by_playerId'
    .set _.omit playerRecord, ['playerId', 'gameRecordTypeId', 'scaledTime']
    .where 'playerId', '=', playerRecord.playerId
    .andWhere 'gameRecordTypeId', '=', playerRecord.gameRecordTypeId
    .andWhere 'scaledTime', '=', playerRecord.scaledTime

    if skipRun
      q
    else
      q.run()

  migrate: (playerId) ->
    console.log 'migratepr'
    knex.select().table 'player_records'
    .where {playerId}
    .map (record) ->
      delete record.id
      record
    .then (playerRecords) ->
      console.log 'migrate pr', playerRecords?.length
      if _.isEmpty playerRecords
        return Promise.resolve null

      chunks = cknex.chunkForBatch playerRecords
      Promise.all _.map chunks, (chunk) ->
        cknex.batchRun _.map chunk, (playerRecord) ->
          playerRecord = defaultPlayerRecord playerRecord
          cknex().update 'player_records_by_playerId'
          .set _.omit playerRecord, [
            'playerId', 'gameRecordTypeId', 'scaledTime'
          ]
          .where 'playerId', '=', playerRecord.playerId
          .andWhere 'gameRecordTypeId', '=', playerRecord.gameRecordTypeId
          .andWhere 'scaledTime', '=', playerRecord.scaledTime
        .catch (err) ->
          console.log err
          null
        # console.log 'migrate records err', playerId
    # .then ->
    # don't need to delete these since they just overwrite if called twice
    #   knex 'player_records'
    #   .where {playerId}
    #   .delete()
    #   .then ->
    #     console.log 'deleted'
    #   .catch (err) ->
    #     console.log 'delete err', err

module.exports = new PlayerRecordModel()
