_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
UserData = require '../models/user_data'
Group = require '../models/group'
Conversation = require '../models/conversation'
GroupRecordType = require '../models/group_record_type'
EmbedService = require '../services/embed'
PushNotificationService = require '../services/push_notification'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.GROUP.USERS
  EmbedService.TYPES.GROUP.CONVERSATIONS
]
channelsEmbed = [
  EmbedService.TYPES.GROUP.USERS
  EmbedService.TYPES.GROUP.CHANNELS
  EmbedService.TYPES.GROUP.CONVERSATIONS
]
userDataEmbed = [
  EmbedService.TYPES.USER.DATA
]
defaultGroupRecordTypes = [
  {name: 'Donations', timeScale: 'week'}
  {name: 'Crowns', timeScale: 'week'}
]

class GroupCtrl
  create: ({name, description, badgeId, background, mode, clanId}, {user}) ->
    creatorId = user.id

    Game.getByKey 'clashRoyale'
    .then ({id}) ->
      Group.create {
        name, description, badgeId, background, creatorId, mode
        userIds: [creatorId]
        gameIds: [id]
        gameData:
          "#{id}":
            clanId: clanId
      }
    .tap ({id}) ->
      Promise.all [
        Conversation.create {
          groupId: id
          name: 'general'
          type: 'group'
        }
        Promise.map defaultGroupRecordTypes, ({name, timeScale}) ->
          GroupRecordType.create {
            name: name
            timeScale: timeScale
            groupId: id
            creatorId: user.id
          }
      ]

  updateById: ({id, name, description, badgeId, background, mode}, {user}) ->
    Group.hasPermissionByIdAndUserId id, user.id, {level: 'admin'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw {status: 400, info: 'You don\'t have permission'}

      Group.updateById id, {name, description, badgeId, background, mode}

  inviteById: ({id, userIds}, {user}) ->
    groupId = id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Promise.all [
      Group.getById groupId
      Promise.map userIds, User.getById
    ]
    .then ([group, toUsers]) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}
      if _.isEmpty toUsers
        router.throw {status: 404, info: 'User not found'}

      hasPermission = Group.hasPermission group, user
      unless hasPermission
        router.throw {status: 400, info: 'You don\'t have permission'}

      Promise.map toUsers, EmbedService.embed userDataEmbed
      .map (toUser) ->
        senderName = User.getDisplayName user
        groupInvitedIds = toUser.data.groupInvitedIds or []
        unreadGroupInvites = toUser.data.unreadGroupInvites or 0
        UserData.upsertByUserId toUser.id, {
          groupInvitedIds: _.uniq groupInvitedIds.concat [id]
          unreadGroupInvites: unreadGroupInvites + 1
        }
        PushNotificationService.send toUser, {
          title: 'New group invite'
          text: "#{senderName} invited you to the group, #{group.name}"
          type: PushNotificationService.TYPES.GROUP
          url: "https://#{config.CLIENT_HOST}"
          data:
            path: "/group/#{group.id}"
        }

      Group.updateById groupId,
        invitedIds: _.uniq group.invitedIds.concat(userIds)

  leaveById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Promise.all [
      EmbedService.embed {embed: userDataEmbed}, user
      Group.getById groupId
    ]
    .then ([user, group]) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      Promise.all [
        UserData.upsertByUserId user.id, {
          groupIds: _.filter user.data.groupIds, (id) -> groupId isnt id
        }
        Group.updateById groupId, {
          userIds: _.filter group.userIds, (id) -> userId isnt id
        }
      ]

  joinById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Promise.all [
      EmbedService.embed {embed: userDataEmbed}, user
      Group.getById groupId
    ]
    .then ([user, group]) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      if group.mode is 'private' and group.invitedIds.indexOf(userId) is -1
        router.throw {status: 401, info: 'Not invited'}

      name = User.getDisplayName user
      PushNotificationService.sendToGroup(group, {
        title: 'New group member'
        text: "#{name} joined your group."
        type: PushNotificationService.TYPES.CREW
        url: "https://#{config.CLIENT_HOST}"
        path: "/group/#{group.id}"
      }, {skipMe: true, meUserId: user.id}).catch -> null

      groupIds = user.data.groupIds or []
      Promise.all [
        UserData.upsertByUserId user.id, {
          groupIds: _.uniq groupIds.concat [groupId]
          invitedIds: _.filter user.data.invitedIds, (id) -> id isnt groupId
        }
        Group.updateById groupId,
          userIds: _.uniq group.userIds.concat([userId])
          invitedIds: _.filter group.invitedIds, (id) -> id isnt userId
      ]

  getAll: ({filter}, {user}) ->
    EmbedService.embed {embed: userDataEmbed}, user
    .then (user) ->
      Group.getAll {filter, user}
    .map EmbedService.embed {embed: defaultEmbed}
    .map Group.sanitize null

  getById: ({id}, {user}) ->
    Group.getById id
    .then EmbedService.embed {embed: channelsEmbed, user}
    .then Group.sanitize null

module.exports = new GroupCtrl()
