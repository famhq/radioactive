_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'
knex = require '../services/knex'
config = require '../config'

GAME_RECORD_TYPE_ID_INDEX = 'gameRecordTypeId'
USER_ID_INDEX = 'userId'
PLAYER_ID_INDEX = 'playerId'
GAME_ID_INDEX = 'gameId'
RECORDS_INDEX = 'records'
RECORD_INDEX = 'record'

fields = [
  {name: 'id', type: 'bigIncrements', index: 'primary'}
  {name: 'userId', type: 'uuid'}
  {name: 'playerId', type: 'string', length: 20, index: 'default'}
  {name: 'gameRecordTypeId', type: 'uuid'}
  {name: 'value', type: 'integer'}
  {name: 'scaledTime', type: 'string', length: 50}
  {name: 'time', type: 'dateTime', defaultValue: new Date()}
]

# TODO: rename userRecord

defaultGameRecord = (gameRecord) ->
  unless gameRecord?
    return null

  _.defaults gameRecord, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

GAME_RECORDS_TABLE = 'game_records'
POSTGRES_GAME_RECORDS_TABLE = 'user_records'

class GameRecordModel
  POSTGRES_TABLES: [
    {
      tableName: POSTGRES_GAME_RECORDS_TABLE
      fields: fields
      indexes: [
        {columns: ['userId', 'gameRecordTypeId', 'scaledTime']}
      ]
    }
  ]
  RETHINK_TABLES: [
    {
      name: GAME_RECORDS_TABLE
      indexes: [
        {name: GAME_RECORD_TYPE_ID_INDEX}
        {name: USER_ID_INDEX}
        {name: PLAYER_ID_INDEX}
        {name: RECORDS_INDEX, fn: (row) ->
          [row('gameRecordTypeId'), row('userId')]}
        {name: RECORD_INDEX, fn: (row) ->
          [row('gameRecordTypeId'), row('userId'), row('scaledTime')]}
      ]
    }
  ]

  batchCreate: (gameRecords) ->
    gameRecords = _.map gameRecords, defaultGameRecord

    knex.insert(gameRecords).into(POSTGRES_GAME_RECORDS_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

    # r.table GAME_RECORDS_TABLE
    # .insert gameRecords
    # .run()
    # .then ->
    #   gameRecords

  create: (gameRecord) ->
    gameRecord = defaultGameRecord gameRecord

    knex.insert(gameRecord).into(POSTGRES_GAME_RECORDS_TABLE)

    # r.table GAME_RECORDS_TABLE
    # .insert gameRecord
    # .run()
    # .then ->
    #   gameRecord

  getAllByUserIdAndGameId: ({userId, gameId}) ->
    if config.IS_POSTGRES
      knex.select().table POSTGRES_GAME_RECORDS_TABLE
      .where {userId}
    else
      r.table GAME_RECORDS_TABLE
      .getAll userId, {index: USER_ID_INDEX}
      .filter {gameId}
      .run()

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
    if config.IS_POSTGRES
      knex.table POSTGRES_GAME_RECORDS_TABLE
      .first '*'
      .where {userId, gameRecordTypeId, scaledTime}
    else
      r.table GAME_RECORDS_TABLE
      .getAll [gameRecordTypeId, userId, scaledTime], {index: RECORD_INDEX}
      .nth 0
      .default null
      .run()

  getRecords: (options) ->
    {gameRecordTypeId, userId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    if config.IS_POSTGRES or true
      knex.select().table POSTGRES_GAME_RECORDS_TABLE
      .where {userId, gameRecordTypeId}
      .andWhere 'scaledTime', '>=', minScaledTime
      .andWhere 'scaledTime', '<=', maxScaledTime
      .orderBy 'scaledTime', 'desc'
      .limit limit
    else
      r.table GAME_RECORDS_TABLE
      .between(
        [gameRecordTypeId, userId, minScaledTime]
        [gameRecordTypeId, userId, maxScaledTime]
        {index: RECORD_INDEX, rightBound: 'closed'}
      )
      .orderBy {index: r.desc RECORD_INDEX}
      .limit limit
      .run()

  duplicateByPlayerId: (playerId, userId) ->
    # TODO: check perf of this
    knex.select().table POSTGRES_GAME_RECORDS_TABLE
    .where {playerId}
    .distinct(knex.raw('ON ("scaledTime") *'))
    .map (record) =>
      delete record.id
      @create _.defaults {
        userId: userId
      }, record

    # r.table GAME_RECORDS_TABLE
    # .getAll playerId, {index: PLAYER_ID_INDEX}
    # .group 'scaledTime'
    # .run()
    # .map ({reduction}) =>
    #   record = reduction[0]
    #   @create _.defaults {
    #     id: uuid.v4()
    #     userId: userId
    #   }, record

module.exports = new GameRecordModel()
