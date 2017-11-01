_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
GroupUser = require '../models/group_user'
GroupRole = require '../models/group_role'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.GROUP_USER.ROLES
]
class GroupCtrl
  createModeratorByUsername: ({groupId, username, roleId}, {user}) ->
    unless user.username is 'austin' # TODO
      router.throw status: 400, info: 'no permission'
    GroupRole.getAllByGroupId groupId
    .then (roles) ->
      if _.isEmpty roles
        GroupRole.upsert {
          groupId: groupId
          globalPermissions: [
            'deleteMessage', 'tempBanUser', 'permaBanUser'
          ]
        }
      else
        roles[0]
    .then (role) ->
      User.getByUsername username
      .then (user) ->
        GroupUser.upsert {
          userId: user.id
          groupId: groupId
          roleIds: ["#{role.roleId}"]
        }

  getByGroupIdAndUserId: ({groupId, userId}, {user}) ->
    GroupUser.getByGroupIdAndUserId groupId, userId
    .then EmbedService.embed {embed: defaultEmbed}

module.exports = new GroupCtrl()
