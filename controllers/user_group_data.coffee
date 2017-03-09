_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

UserGroupData = require '../models/user_group_data'
Group = require '../models/group'
EmbedService = require '../services/embed'

class UserGroupData
  getMeByGroupId: ({groupId}, {user}) ->
    Group.hasPermissionByIdAndUserId groupId, user.id, {level: 'member'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      UserGroupData.getByUserIdAndGroupId user.id, groupId

  updateMeByGroupId: ({groupId, globalBlockedNotifications}, {user}) ->
    Group.hasPermissionByIdAndUserId groupId, user.id, {level: 'member'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      UserGroupData.upsertByUserIdAndGroupId user.id, groupId, {
        globalBlockedNotifications: globalBlockedNotifications
      }

module.exports = new UserGroupData()
