_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

cknex = require '../services/cknex'
TimeService = require '../services/time'
config = require '../config'

tables = [
  {
    name: 'group_records_counter_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      recordTypeKey: 'text'
      value: 'counter'
      scaledTime: 'text'
    primaryKey:
      partitionKey: ['groupId', 'recordTypeKey']
      clusteringColumns: ['scaledTime']
    withClusteringOrderBy: ['scaledTime', 'desc']
  }
]

defaultGroupRecord = (groupRecord) ->
  unless groupRecord?
    return null

  _.defaults groupRecord, {
    scaledTime: TimeService.getScaledTimeByTimeScale 'day'
  }

class GroupRecordModel
  SCYLLA_TABLES: tables

  getAllByGroupIdAndRecordTypeKey: (groupId, recordTypeKey, options = {}) ->
    {minScaledTime, maxScaledTime, limit} = options
    limit ?= 30
    limit = Math.min limit, 100
    minScaledTime ?= TimeService.getScaledTimeByTimeScale(
      'day', moment().subtract(14, 'd')
    )
    maxScaledTime ?= TimeService.getScaledTimeByTimeScale 'day'

    cknex().select '*'
    .from 'group_records_counter_by_groupId'
    .where 'groupId', '=', groupId
    .where 'recordTypeKey', '=', recordTypeKey
    .where 'scaledTime', '>=', minScaledTime
    .where 'scaledTime', '<=', maxScaledTime
    .limit limit
    .run()

  incrementByGroupIdAndRecordTypeKey: (groupId, recordTypeKey, amount) ->
    cknex().update 'group_records_counter_by_groupId'
    .increment 'value', amount
    .where 'groupId', '=', groupId
    .andWhere 'recordTypeKey', '=', recordTypeKey
    .andWhere 'scaledTime', '=', TimeService.getScaledTimeByTimeScale 'day'
    .run()

module.exports = new GroupRecordModel()
