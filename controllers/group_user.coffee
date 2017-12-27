_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
GroupUser = require '../models/group_user'
GroupRole = require '../models/group_role'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
config = require '../config'

FIVE_MINUTES_SECONDS = 60 * 5

defaultEmbed = [
  EmbedService.TYPES.GROUP_USER.ROLES
  EmbedService.TYPES.GROUP_USER.XP
]
userEmbed = [
  EmbedService.TYPES.GROUP_USER.USER
]
class GroupUserCtrl
  addRoleByGroupIdAndUserId: ({groupId, userId, roleId}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['manageRoles']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupRole.getAllByGroupId groupId
      .then (roles) ->
        role = _.find roles, (role) ->
          "#{role.roleId}" is roleId
        unless role
          router.throw status: 404, info: 'no role exists'
        GroupUser.addRoleIdByGroupUser {
          userId: userId
          groupId: groupId
        }, roleId

  removeRoleByGroupIdAndUserId: ({groupId, userId, roleId}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['manageRoles']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'
      GroupRole.getAllByGroupId groupId
      .then (roles) ->
        role = _.find roles, (role) ->
          "#{role.roleId}" is roleId
        unless role
          router.throw status: 404, info: 'no role exists'
        GroupUser.removeRoleIdByGroupUser {
          userId: userId
          groupId: groupId
        }, roleId

  getByGroupIdAndUserId: ({groupId, userId}, {user}) ->
    GroupUser.getByGroupIdAndUserId groupId, userId
    .then EmbedService.embed {embed: defaultEmbed}

  getTopByGroupId: ({groupId}, {user}) ->
    key = "#{CacheService.PREFIXES.GROUP_USER_TOP}:#{groupId}"
    CacheService.preferCache key, ->
      GroupUser.getTopByGroupId groupId
      .map EmbedService.embed {embed: userEmbed}
    , {expireSeconds: FIVE_MINUTES_SECONDS}

module.exports = new GroupUserCtrl()
