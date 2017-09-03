_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

knex = require '../services/knex'
config = require '../config'

fields = [
  {name: 'id', type: 'bigIncrements', index: 'primary'}
  {name: 'playerId', type: 'string', length: 20}
  {name: 'gameRecordTypeId', type: 'uuid'}
  {name: 'value', type: 'integer'}
  {name: 'scaledTime', type: 'string', length: 50, index: 'default'}
  {name: 'time', type: 'dateTime', defaultValue: new Date(), index: 'default'}
]

defaultPlayerRecord = (playerRecord) ->
  unless playerRecord?
    return null

  _.defaults playerRecord, _.reduce(fields, (obj, field) ->
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

PLAYER_RECORDS_TABLE = 'player_records'

class PlayerRecordModel
  POSTGRES_TABLES: [
    {
      tableName: PLAYER_RECORDS_TABLE
      fields: fields
      indexes: [
        {
          columns: ['playerId', 'gameRecordTypeId', 'scaledTime']
          type: 'unique'
        }
      ]
    }
  ]

  batchCreate: (playerRecords) ->
    playerRecords = _.map playerRecords, defaultPlayerRecord

    knex.insert(playerRecords).into(PLAYER_RECORDS_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

  create: (playerRecord) ->
    playerRecord = defaultPlayerRecord playerRecord

    knex.insert(playerRecord).into(PLAYER_RECORDS_TABLE)

  getAllByPlayerIdAndGameId: ({playerId, gameId}) ->
    knex.select().table PLAYER_RECORDS_TABLE
    .where {playerId}

  getScaledTimeByTimeScale: (timeScale, time) ->
    time ?= moment()
    if timeScale is 'day'
      'DAY-' + time.format 'YYYY-MM-DD'
    else if timeScale is 'biweek'
      'BIWEEK-' + time.format('YYYY') + (parseInt(time.format 'YYYY-W') / 2)
    else if timeScale is 'week'
      'WEEK-' + time.format 'YYYY-W'
    else
      time.format time.format 'YYYY-MM-DD HH:mm'

  getRecord: ({gameRecordTypeId, playerId, scaledTime}) ->
    knex.table PLAYER_RECORDS_TABLE
    .first '*'
    .where {playerId, gameRecordTypeId, scaledTime}

  getRecords: (options) ->
    {gameRecordTypeId, playerId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    knex.select().table PLAYER_RECORDS_TABLE
    .where {playerId, gameRecordTypeId}
    .andWhere 'scaledTime', '>=', minScaledTime
    .andWhere 'scaledTime', '<=', maxScaledTime
    .orderBy 'scaledTime', 'desc'
    .limit limit

  upsert: ({playerId, gameRecordTypeId, scaledTime, diff}) ->
    upsert {
      table: PLAYER_RECORDS_TABLE
      diff: defaultPlayerRecord _.defaults {
        playerId, gameRecordTypeId, scaledTime
      }, diff
      constraint: '("playerId", "gameRecordTypeId", "scaledTime")'
    }

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
        console.log err

module.exports = new PlayerRecordModel()
