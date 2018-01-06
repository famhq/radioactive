_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

config = require '../config'
cknex = require '../services/cknex'

ONE_DAY_SECONDS = 3600 * 24
THREE_HOURS_SECONDS = 3600 * 3
SIXTY_DAYS_SECONDS = 60 * 3600 * 24

defaultGroupAuditLog = (groupAuditLog) ->
  unless groupAuditLog?
    return null

  _.defaults groupAuditLog, {
    timeUuid: cknex.getTimeUuid()
  }


tables = [
  {
    name: 'group_audit_log_by_timeUuid'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      actionText: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
]

class GroupAuditLogModel
  SCYLLA_TABLES: tables

  upsert: (groupAuditLog) ->
    groupAuditLog = defaultGroupAuditLog(
      groupAuditLog
    )

    cknex().update 'group_audit_log_by_timeUuid'
    .set _.omit groupAuditLog, [
      'groupId', 'timeUuid'
    ]
    .andWhere 'groupId', '=', groupAuditLog.groupId
    .andWhere 'timeUuid', '=', groupAuditLog.timeUuid
    .usingTTL SIXTY_DAYS_SECONDS
    .run()
    .then ->
      groupAuditLog

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'group_audit_log_by_timeUuid'
    .where 'groupId', '=', groupId
    .limit 30
    .run()

module.exports = new GroupAuditLogModel()
