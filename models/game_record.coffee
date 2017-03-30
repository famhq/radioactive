_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'

GAME_RECORD_TYPE_ID_INDEX = 'gameRecordTypeId'
SCALED_TIME_INDEX = 'scaledTime'
USER_ID_INDEX = 'userId'
PLAYER_ID_INDEX = 'playerId'
GAME_ID_INDEX = 'gameId'
RECORDS_INDEX = 'records'
RECORD_INDEX = 'record'
GAME_RECORD_TYPE_TIME_INDEX = 'gameRecordTypeTime'

defaultGameRecord = (gameRecord) ->
  unless gameRecord?
    return null

  _.defaults gameRecord, {
    id: uuid.v4()
    userId: null
    playerId: null
    gameRecordTypeId: null
    value: 0
    scaledTime: null
    time: new Date()
  }

GAME_RECORDS_TABLE = 'game_records'

class GameRecordModel
  RETHINK_TABLES: [
    {
      name: GAME_RECORDS_TABLE
      indexes: [
        {name: GAME_RECORD_TYPE_ID_INDEX}
        {name: USER_ID_INDEX}
        {name: PLAYER_ID_INDEX}
        {name: SCALED_TIME_INDEX}
        {name: RECORDS_INDEX, fn: (row) ->
          [row('gameRecordTypeId'), row('userId')]}
        {name: RECORD_INDEX, fn: (row) ->
          [row('gameRecordTypeId'), row('userId'), row('scaledTime')]}
        {name: GAME_RECORD_TYPE_TIME_INDEX, fn: (row) ->
          [row('gameRecordTypeId'), row('scaledTime')]}
      ]
    }
  ]

  batchCreate: (gameRecords) ->
    gameRecords = _.map gameRecords, defaultGameRecord

    r.table GAME_RECORDS_TABLE
    .insert gameRecords
    .run()
    .then ->
      gameRecords

  create: (gameRecord) ->
    gameRecord = defaultGameRecord gameRecord

    r.table GAME_RECORDS_TABLE
    .insert gameRecord
    .run()
    .then ->
      gameRecord

  getAllByUserIdAndGameId: ({userId, gameId}) ->
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
    r.table GAME_RECORDS_TABLE
    .getAll [gameRecordTypeId, userId, scaledTime], {index: RECORD_INDEX}
    .nth 0
    .default null
    .run()

  getRecords: (options) ->
    {gameRecordTypeId, userId, minScaledTime, maxScaledTime, limit} = options
    limit ?= 30

    r.table GAME_RECORDS_TABLE
    .between(
      [gameRecordTypeId, userId, minScaledTime]
      [gameRecordTypeId, userId, maxScaledTime]
      {index: RECORD_INDEX, rightBound: 'closed'}
    )
    .orderBy {index: r.desc RECORD_INDEX}
    .limit limit
    .run()

  getAllRecordsByTypeAndTime: ({gameRecordTypeId, scaledTime}) ->
    r.table GAME_RECORDS_TABLE
    .getAll [gameRecordTypeId, scaledTime], {index: GAME_RECORD_TYPE_TIME_INDEX}
    .run()

  duplicateByPlayerId: (playerId, userId) ->
    r.table GAME_RECORDS_TABLE
    .getAll playerId, {index: PLAYER_ID_INDEX}
    .group 'scaledTime'
    .run()
    .map ({reduction}) =>
      record = reduction[0]
      @create _.defaults {
        id: uuid.v4()
        userId: userId
      }, record

  updateById: (id, diff) ->
    r.table GAME_RECORDS_TABLE
    .get id
    .update diff
    .run()

module.exports = new GameRecordModel()
