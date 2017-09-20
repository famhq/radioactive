_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

knex = require '../services/knex'
config = require '../config'

fields = [
  {name: 'id', type: 'bigIncrements', index: 'primary'}
  {name: 'clanId', type: 'string', length: 20}
  {name: 'clanRecordTypeId', type: 'uuid'}
  {name: 'value', type: 'integer'}
  {name: 'scaledTime', type: 'string', length: 50}
  {name: 'time', type: 'dateTime', defaultValue: new Date()}
]

defaultClanRecord = (clanRecord) ->
  unless clanRecord?
    return null

  _.defaults clanRecord, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

upsert = ({table, diff, constraint}) ->
  insert = knex(table).insert(diff)
  update = knex.queryBuilder().update(diff)

  knex.raw "? ON CONFLICT #{constraint} DO ? returning *", [insert, update]
  .then (result) -> result.rows[0]

CLAN_RECORDS_TABLE = 'clan_records'

class ClanRecordModel
  POSTGRES_TABLES: [
    {
      tableName: CLAN_RECORDS_TABLE
      fields: fields
      indexes: [
        {
          columns: ['clanId', 'clanRecordTypeId', 'scaledTime']
          type: 'unique'
        }
      ]
    }
  ]

  batchCreate: (clanRecords) ->
    clanRecords = _.map clanRecords, defaultClanRecord

    knex.insert(clanRecords).into(CLAN_RECORDS_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

  create: (clanRecord) ->
    clanRecord = defaultClanRecord clanRecord

    knex.insert(clanRecord).into(CLAN_RECORDS_TABLE)

  getAllByClanIdAndGameId: ({clanId, gameId}) ->
    knex.select().table CLAN_RECORDS_TABLE
    .where {clanId}

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
    knex.table CLAN_RECORDS_TABLE
    .first '*'
    .where {clanId, clanRecordTypeId, scaledTime}

  getRecords: (options) ->
    {clanRecordTypeId, clanId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    knex.select().table CLAN_RECORDS_TABLE
    .where {clanId, clanRecordTypeId}
    .andWhere 'scaledTime', '>=', minScaledTime
    .andWhere 'scaledTime', '<=', maxScaledTime
    .orderBy 'scaledTime', 'desc'
    .limit limit

  upsert: ({clanId, clanRecordTypeId, scaledTime, diff}) ->
    upsert {
      table: CLAN_RECORDS_TABLE
      diff: defaultClanRecord _.defaults {
        clanId, clanRecordTypeId, scaledTime
      }, diff
      constraint: '("clanId", "clanRecordTypeId", "scaledTime")'
    }

module.exports = new ClanRecordModel()
