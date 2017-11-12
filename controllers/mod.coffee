_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
GroupUser = require '../models/group_user'
ChatMessage = require '../models/chat_message'
Ban = require '../models/ban'
EmbedService = require '../services/embed'
config = require '../config'

BANNED_LIMIT = 15

# TODO: this probably should be deleted and the methods moved to
# each respective controller (chat_message, user, etc...)
class ModCtrl
  getAllBanned: ({groupId, duration, scope} = {}, {user}) ->
    unless user.flags.isModerator
      router.throw status: 400, info: 'You don\'t have permission to do that'

    groupId ?= config.MAIN_GROUP_ID
    duration ?= '24h'
    scope ?= 'chat'

    Ban.getAll {groupId, duration, scope}
    .map EmbedService.embed {
      embed: [EmbedService.TYPES.BAN.USER]
    }

  getAllReportedMessages: ({}, {user}) ->
    unless user.flags.isModerator
      router.throw status: 400, info: 'You don\'t have permission to do that'

    ChatMessage.getAllReported {limit: BANNED_LIMIT}
    .map ChatMessage.embed ['user']

  banByUserId: ({userId, groupId, duration, type}, {user}) ->
    GroupUser.getByGroupIdAndUserId groupId, userId
    .then (groupUser) ->
      permission = if duration is 'permanent' \
                   then 'permaBanUser'
                   else 'tempBanUser'
      hasPermission = GroupUser.hasPermission {
        groupId, meGroupUser: groupUser, me: user, permissions: [permission]
      }

      unless hasPermission
        router.throw status: 400, info: 'You don\'t have permission to do that'

      ban = {userId, groupId, duration, bannedById: user.id, scope: 'chat'}

      User.getById userId
      .then (user) ->
        unless user
          router.throw status: 404, info: 'User not found'
        if type is 'ip'
          ban.ip = user.lastActiveIp or user.ip
        if ban.ip?.indexOf('::ffff:10.') isnt -1
          delete ban.ip # TODO: remove. ignores local ips (which shouldn't happen)

        Ban.create ban
    .then ->
      if groupId
        ChatMessage.deleteAllByGroupIdAndUserId groupId, userId

  unbanByUserId: ({userId, groupId}, {user}) ->
    GroupUser.getByGroupIdAndUserId groupId, userId
    .then (groupUser) ->
      permission = 'tempBanUser'
      hasPermission = GroupUser.hasPermission {
        groupId, meGroupUser: groupUser, me: user, permissions: [permission]
      }
    unless hasPermission
      router.throw status: 400, info: 'You don\'t have permission to do that'

    Ban.deleteAllByUserId userId

  # unflagByChatMessageId: ({id}, {user}) ->
  #   GroupUser.getByGroupIdAndUserId groupId, userId
  #   .then (groupUser) ->
  #     permission = 'tempBan'
  #     hasPermission = GroupUser.hasPermission {
  #       groupId, meGroupUser: groupUser, me: user, permissions: [permission]
  #     }
  #   unless hasPermission
  #     router.throw status: 400, info: 'You don\'t have permission to do that'
  #
  #   ChatMessage.updateById id, {hasModActed: true}

module.exports = new ModCtrl()
