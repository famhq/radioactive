_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'clan_records_by_clanId'
    fields:
      clanId: 'text'
      clanRecordTypeId: 'uuid'
      value: 'int'
      scaledTime: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['clanId', 'clanRecordTypeId']
      clusteringColumns: ['scaledTime']
    withClusteringOrderBy: ['scaledTime', 'desc']
  }
]

defaultClanRecord = (clanRecord) ->
  unless clanRecord?
    return null

  _.defaults clanRecord, {
    time: new Date()
  }

class ClanRecordModel
  SCYLLA_TABLES: tables

  batchCreate: (clanRecords) ->
    if _.isEmpty clanRecords
      return Promise.resolve null
    cknex.batchRun _.map clanRecords, (clanRecord) ->
      clanRecord = defaultClanRecord clanRecord
      cknex().update 'clan_records_by_clanId'
      .set _.omit clanRecord, ['clanId', 'clanRecordTypeId', 'scaledTime']
      .where 'clanId', '=', clanRecord.clanId
      .andWhere 'clanRecordTypeId', '=', clanRecord.clanRecordTypeId
      .andWhere 'scaledTime', '=', clanRecord.scaledTime

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

  getRecord: ({clanRecordTypeId, clanId, scaledTime}) ->
    cknex().select '*'
    .from 'clan_records_by_clanId'
    .where 'clanId', '=', clanId
    .andWhere 'clanRecordTypeId', '=', clanRecordTypeId
    .andWhere 'scaledTime', '=', scaledTime
    .run {isSingle: true}

  getRecords: (options) ->
    {clanRecordTypeId, clanId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    cknex().select '*'
    .from 'clan_records_by_clanId'
    .where 'clanId', '=', clanId
    .where 'clanRecordTypeId', '=', clanRecordTypeId
    .where 'scaledTime', '>=', minScaledTime
    .where 'scaledTime', '<=', maxScaledTime
    .limit limit
    .run()

  upsert: ({clanId, clanRecordTypeId, scaledTime, diff}) ->
    clanRecord = defaultClanRecord clanRecord
    cknex().update 'clan_records_by_clanId'
    .set _.omit diff, ['clanId', 'clanRecordTypeId', 'scaledTime']
    .where 'clanId', '=', clanId
    .andWhere 'clanRecordTypeId', '=', clanRecordTypeId
    .andWhere 'scaledTime', '=', scaledTime
    .run()

module.exports = new ClanRecordModel()
