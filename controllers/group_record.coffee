_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
moment = require 'moment'

GroupRecord = require '../models/group_record'
Group = require '../models/group'
EmbedService = require '../services/embed'

class GroupRecordCtrl
  getAllByGroupIdAndRecordTypeKey: (options, {user}) ->
    {groupId, recordTypeKey, minScaledTime, maxScaledTime, limit} = options
    GroupRecord.getAllByGroupIdAndRecordTypeKey groupId, recordTypeKey, {
      minScaledTime, maxScaledTime, limit
    }

module.exports = new GroupRecordCtrl()
