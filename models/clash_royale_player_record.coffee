_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'player_records_by_playerId'
    keyspace: 'clash_royale'
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
    queries = _.filter _.flatten _.map matches, (match) =>
      if match.type is 'PvP'
        scaledTime = @getScaledTimeByTimeScale(
          'minute', match.momentTime
        )
        players = match.data.team.concat match.data.opponent
        _.map players, (player, i) =>
          value = player.startingTrophies + player.trophyChange
          if isNaN value
            return
          record = {
            playerId: player.tag.replace '#', ''
            gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
            scaledTime
            time: match.time
            value: value
          }
          @upsert record, {skipRun: true}

    if _.isEmpty queries
      return Promise.resolve null

    cknex.batchRun queries

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
    cknex('clash_royale').select '*'
    .from 'player_records_by_playerId'
    .where 'playerId', '=', playerId
    .andWhere 'gameRecordTypeId', '=', gameRecordTypeId
    .andWhere 'scaledTime', '=', scaledTime
    .run {isSingle: true}

  getRecords: (options) ->
    {gameRecordTypeId, playerId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    cknex('clash_royale').select '*'
    .from 'player_records_by_playerId'
    .where 'playerId', '=', playerId
    .where 'gameRecordTypeId', '=', gameRecordTypeId
    .where 'scaledTime', '>=', minScaledTime
    .where 'scaledTime', '<=', maxScaledTime
    .limit limit
    .run()

  upsert: (playerRecord, {skipRun} = {}) ->
    playerRecord = defaultPlayerRecord playerRecord
    q = cknex('clash_royale').update 'player_records_by_playerId'
    .set {
      value: playerRecord.value
      time: playerRecord.time
    }
    .where 'playerId', '=', playerRecord.playerId
    .andWhere 'gameRecordTypeId', '=', playerRecord.gameRecordTypeId
    .andWhere 'scaledTime', '=', playerRecord.scaledTime

    if skipRun
      q
    else
      q.run()

module.exports = new PlayerRecordModel()
