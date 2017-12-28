_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

GroupRole = require '../models/group_role'
GroupUser = require '../models/group_user'
config = require '../config'

class GroupRoleCtrl
  getAllByGroupId: ({groupId}, {user}) ->
    GroupRole.getAllByGroupId groupId

  createByGroupId: ({groupId, name}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['manageRoles']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupRole.upsert {
        groupId: groupId
        name: name
        globalPermissions: {}
      }

  updatePermissions: (params, {user}) ->
    {groupId, roleId, channelId, permissions} = params
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['manageRoles']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      mapOptions = {
        map:
          channelPermissions:
            "#{channelId}": JSON.stringify permissions
      }
      diff = {
        groupId
        roleId
      }
      if not channelId
        diff.globalPermissions = permissions
      GroupRole.upsert diff, if channelId then mapOptions else undefined

module.exports = new GroupRoleCtrl()
