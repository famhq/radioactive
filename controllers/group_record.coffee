_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
moment = require 'moment'

GroupRecord = require '../models/group_record'
GroupRecordType = require '../models/group_record_type'
Group = require '../models/group'
EmbedService = require '../services/embed'

class GroupRecordCtrl
  save: ({userId, groupRecordTypeId, value}, {user}) ->
    GroupRecordType.getById groupRecordTypeId
    .then (groupRecordType) ->
      Group.hasPermissionByIdAndUserId groupRecordType.groupId, user.id, {level:
        'admin'
      }
      .then (hasPermission) ->
        unless hasPermission
          router.throw status: 400, info: 'no permission'

        scaledTime = GroupRecord.getScaledTimeByTimeScale(
          groupRecordType.timeScale
        )

        GroupRecord.getRecord {scaledTime, userId, groupRecordTypeId}
        .then (groupRecord) ->
          if groupRecord
            GroupRecord.updateById groupRecord.id, {value}
          else
            GroupRecord.create {userId, groupRecordTypeId, scaledTime, value}


  bulkSave: ({changes}, {user}) =>
    Promise.map changes, (change) =>
      @save change, {user}

  # getById: ({id}, {user}) ->
  #   GroupRecord.getById id
  #   .then GroupRecord.sanitize null

  getAllByUserIdAndGroupId: ({userId, groupId}, {user}) ->
    unless userId
      router.throw status: 404, info: 'user not found'

    Group.hasPermissionByIdAndUserId groupId, user.id, {level: 'admin'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupRecordType.getAllByGroupId groupId
      .map (recordType) ->
        {id, timeScale} = recordType
        currentScaledTime = GroupRecord.getScaledTimeByTimeScale timeScale
        pastScaledTime = GroupRecord.getScaledTimeByTimeScale(
          timeScale, moment().subtract(8, timeScale)
        )
        GroupRecord.getRecords {
          groupRecordTypeId: id
          userId: userId
          minScaledTime: pastScaledTime
          maxScaledTime: currentScaledTime
        }
        .then (records) ->
          {recordType, records}

module.exports = new GroupRecordCtrl()
