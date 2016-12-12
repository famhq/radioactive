_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Group = require '../models/group'
EmbedService = require '../services/embed'
PushNotificationService = require '../services/push_notification'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.GROUP.USERS
]

class GroupCtrl
  create: ({name, description, badgeId, background}, {user}) ->
    creatorId = user.id

    Group.create {
      name, description, badgeId, background, creatorId, userIds: [creatorId]
    }

  updateById: ({id, name, description, badgeId, background}, {user}) ->
    Group.updateById id, {name, description, badgeId, background}

  joinById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      throw new router.Error {status: 404, detail: 'Group not found'}

    Group.getById groupId
    .then (group) ->
      unless group
        throw new router.Error {status: 404, detail: 'Group not found'}

      if group.isInviteOnly and group.invitedIds.indexOf(userId) is -1
        throw new router.Error {status: 401, detail: 'Not invited'}

      name = User.getDisplayName user
      PushNotificationService.sendToGroup(group, {
        title: 'New group member'
        text: "#{name} joined your group."
        type: PushNotificationService.TYPES.CREW
        url: "https://#{config.CLIENT_HOST}"
        path: "/group/#{group.id}"
      }, {skipMe: true, meUserId: user.id}).catch -> null

      Promise.all [
        Group.updateById groupId,
          userIds: _.uniq group.userIds.concat([userId])
          invitedIds: _.filter group.invitedIds, (id) -> id isnt userId
      ]

  getAll: ({filter}, {user}) ->
    Group.getAll {filter, userId: user.id}
    .map EmbedService.embed defaultEmbed
    .map Group.sanitize null

  getById: ({id}, {user}) ->
    Group.getById id
    .then EmbedService.embed defaultEmbed
    .then Group.sanitize null

module.exports = new GroupCtrl()
