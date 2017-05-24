_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

knex = require '../services/knex'
config = require '../config'

fields = [
  {name: 'id', type: 'bigIncrements', index: 'primary'}
  {name: 'userId', type: 'uuid'}
  {name: 'playerId', type: 'string', length: 20, index: 'default'}
  {name: 'gameRecordTypeId', type: 'uuid'}
  {name: 'value', type: 'integer'}
  {name: 'scaledTime', type: 'string', length: 50, index: 'default'}
  {name: 'time', type: 'dateTime', defaultValue: new Date(), index: 'default'}
]

defaultUserRecord = (userRecord) ->
  unless userRecord?
    return null

  _.defaults userRecord, _.reduce(fields, (obj, field) ->
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

USER_RECORDS_TABLE = 'user_records'

class UserRecordModel
  POSTGRES_TABLES: [
    {
      tableName: USER_RECORDS_TABLE
      fields: fields
      indexes: [
        {
          columns: ['userId', 'gameRecordTypeId', 'scaledTime']
          type: 'unique'
        }
      ]
    }
  ]

  batchCreate: (userRecords) ->
    userRecords = _.map userRecords, defaultUserRecord

    knex.insert(userRecords).into(USER_RECORDS_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

  create: (userRecord) ->
    userRecord = defaultUserRecord userRecord

    knex.insert(userRecord).into(USER_RECORDS_TABLE)

  getAllByUserIdAndGameId: ({userId, gameId}) ->
    knex.select().table USER_RECORDS_TABLE
    .where {userId}

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

  getRecord: ({gameRecordTypeId, userId, scaledTime}) ->
    knex.table USER_RECORDS_TABLE
    .first '*'
    .where {userId, gameRecordTypeId, scaledTime}

  getRecords: (options) ->
    {gameRecordTypeId, userId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    knex.select().table USER_RECORDS_TABLE
    .where {userId, gameRecordTypeId}
    .andWhere 'scaledTime', '>=', minScaledTime
    .andWhere 'scaledTime', '<=', maxScaledTime
    .orderBy 'scaledTime', 'desc'
    .limit limit

  upsert: ({userId, gameRecordTypeId, scaledTime, diff}) ->
    upsert {
      table: USER_RECORDS_TABLE
      diff: defaultUserRecord _.defaults {
        userId, gameRecordTypeId, scaledTime
      }, diff
      constraint: '("userId", "gameRecordTypeId", "scaledTime")'
    }

  duplicateByPlayerId: (playerId, userId) ->
    # TODO: check perf of this
    knex.select().table USER_RECORDS_TABLE
    .where {playerId}
    .distinct(knex.raw('ON ("scaledTime") *'))
    .map (record) =>
      delete record.id
      @create _.defaults {
        userId: userId
      }, record
      .catch (err) ->
        console.log err

module.exports = new UserRecordModel()
