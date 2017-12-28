_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
GroupUser = require '../models/group_user'
ChatMessage = require '../models/chat_message'
Ban = require '../models/ban'
EmbedService = require '../services/embed'
config = require '../config'

BANNED_LIMIT = 15

class BanCtrl
  getAllByGroupId: ({groupId, duration} = {}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['banUsers']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      groupId ?= config.MAIN_GROUP_ID
      duration ?= '24h'

      Ban.getAllByGroupIdAndDuration groupId, duration
      .map EmbedService.embed {
        embed: [EmbedService.TYPES.BAN.USER]
      }

  banByGroupIdAndUserId: ({userId, groupId, duration, type}, {user}) ->
    permission = if duration is 'permanent' \
                 then 'permaBanUser'
                 else 'tempBanUser'
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, [permission]
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      ban = {userId, groupId, duration, bannedById: user.id}

      User.getById userId
      .then (user) ->
        unless user
          router.throw status: 404, info: 'User not found'
        if type is 'ip'
          ban.ip = user.lastActiveIp or user.ip
        if ban.ip?.indexOf('::ffff:10.') isnt -1
          delete ban.ip # TODO: remove. ignores local ips (which shouldn't happen)

        Ban.upsert ban
    .then ->
      if groupId
        ChatMessage.deleteAllByGroupIdAndUserId groupId, userId

  unbanByGroupIdAndUserId: ({userId, groupId}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, ['unbanUser']
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      Ban.deleteAllByUserId userId

module.exports = new BanCtrl()
