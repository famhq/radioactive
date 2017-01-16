_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

GroupUserData = require '../models/group_user_data'
Group = require '../models/group'
EmbedService = require '../services/embed'

class GroupUserDataCtrl
  getMeByGroupId: ({groupId}, {user}) ->
    Group.hasPermissionById groupId, user.id, {level: 'member'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupUserData.getByUserIdAndGroupId user.id, groupId

  updateMeByGroupId: ({groupId, globalBlockedNotifications}, {user}) ->
    Group.hasPermissionById groupId, user.id, {level: 'member'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupUserData.upsertByUserIdAndGroupId user.id, groupId, {
        globalBlockedNotifications: globalBlockedNotifications
      }

module.exports = new GroupUserDataCtrl()
