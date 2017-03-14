_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'

GROUP_RECORD_TYPE_ID_INDEX = 'groupRecordTypeId'
SCALED_TIME_INDEX = 'scaledTime'
USER_ID_INDEX = 'userId'
GROUP_ID_INDEX = 'groupId'
RECORD_INDEX = 'record'
RECORD_GROUP_TYPE_TIME_INDEX = 'recordGroupTypeTime'

# TODO: rm this model?

defaultGroupRecord = (groupRecord) ->
  unless groupRecord?
    return null

  _.defaults groupRecord, {
    id: uuid.v4()
    creatorId: null
    userId: null
    groupRecordTypeId: null
    value: 0
    scaledTime: null
    time: new Date()
  }

GROUP_RECORDS_TABLE = 'group_records'

class GroupRecordModel
  RETHINK_TABLES: [
    {
      name: GROUP_RECORDS_TABLE
      indexes: [
        {name: GROUP_RECORD_TYPE_ID_INDEX}
        {name: USER_ID_INDEX}
        {name: SCALED_TIME_INDEX}
        {name: RECORD_INDEX, fn: (row) ->
          [row('groupRecordTypeId'), row('userId'), row('scaledTime')]}
        {name: RECORD_GROUP_TYPE_TIME_INDEX, fn: (row) ->
          [row('groupRecordTypeId'), row('scaledTime')]}
      ]
    }
  ]

  create: (groupRecord) ->
    groupRecord = defaultGroupRecord groupRecord

    r.table GROUP_RECORDS_TABLE
    .insert groupRecord
    .run()
    .then ->
      groupRecord

  getAllByUserIdAndGroupId: ({userId, groupId}) ->
    r.table GROUP_RECORDS_TABLE
    .getAll groupId, {index: USER_ID_INDEX}
    .filter {groupId}
    .run()

  getAllByGroupRecordTypeId: (groupRecordTypeId) ->
    r.table GROUP_RECORDS_TABLE
    .getAll groupRecordTypeId, {index: GROUP_RECORD_TYPE_ID_INDEX}
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

  getRecord: ({groupRecordTypeId, userId, scaledTime}) ->
    r.table GROUP_RECORDS_TABLE
    .getAll [groupRecordTypeId, userId, scaledTime], {index: RECORD_INDEX}
    .nth 0
    .default null
    .run()

  getRecords: ({groupRecordTypeId, userId, minScaledTime, maxScaledTime}) ->
    r.table GROUP_RECORDS_TABLE
    .between(
      [groupRecordTypeId, userId, minScaledTime]
      [groupRecordTypeId, userId, maxScaledTime]
      {index: RECORD_INDEX, rightBound: 'closed'}
    )
    .run()

  getAllRecordsByTypeAndTime: ({groupRecordTypeId, scaledTime}) ->
    r.table GROUP_RECORDS_TABLE
    .getAll [groupRecordTypeId, scaledTime], {
      index: RECORD_GROUP_TYPE_TIME_INDEX
    }
    .orderBy r.desc RECORD_GROUP_TYPE_TIME_INDEX
    .run()

  updateById: (id, diff) ->
    r.table GROUP_RECORDS_TABLE
    .get id
    .update diff
    .run()

module.exports = new GroupRecordModel()
