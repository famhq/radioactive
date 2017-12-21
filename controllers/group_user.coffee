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
  createModeratorByUsername: ({groupId, username, roleId}, {user}) ->
    unless user.username is 'austin' # TODO
      router.throw status: 400, info: 'no permission'
    GroupRole.getAllByGroupId groupId
    .then (roles) ->
      if _.isEmpty roles
        GroupRole.upsert {
          groupId: groupId
          name: 'mods'
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

  getTopByGroupId: ({groupId}, {user}) ->
    key = "#{CacheService.PREFIXES.GROUP_USER_TOP}:#{groupId}"
    CacheService.preferCache key, ->
      GroupUser.getTopByGroupId groupId
      .map EmbedService.embed {embed: userEmbed}
    , {expireSeconds: FIVE_MINUTES_SECONDS}

module.exports = new GroupUserCtrl()
