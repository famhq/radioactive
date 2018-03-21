_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
Group = require '../models/group'
GroupUser = require '../models/group_user'
GroupRole = require '../models/group_role'
Clan = require '../models/clan'
Game = require '../models/game'
Conversation = require '../models/conversation'
GroupRecordType = require '../models/group_record_type'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.GROUP.ME_GROUP_USER
  EmbedService.TYPES.GROUP.STAR
  EmbedService.TYPES.GROUP.USER_COUNT
]
userDataEmbed = [
  EmbedService.TYPES.USER.DATA
]
defaultGroupRecordTypes = [
  {name: 'Donations', timeScale: 'week'}
  {name: 'Crowns', timeScale: 'week'}
]

THIRTY_MINUTES_SECONDS = 60 * 5

class GroupCtrl
  create: ({name, description, badgeId, background, mode, clanId}, {user}) ->
    creatorId = user.id

    # Game.getByKey 'clashRoyale'
    Promise.resolve {id: 'clash-royale'}
    .then ({id}) ->
      Group.create {
        name, description, badgeId, background, creatorId, mode
        gameKeys: [id]
        gameData:
          "#{id}":
            clanId: clanId
      }
    .tap ({id}) ->
      Promise.all [
        Group.addUser id, user.id
        GroupRole.upsert {
          groupId: id
          name: 'everyone'
          globalPermissions: {}
        }
        Conversation.upsert {
          groupId: id
          data:
            name: 'general'
          type: 'channel'
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

  # FIXME: need to add some notion of invitedIds for group_users
  # inviteById: ({id, userIds}, {user}) ->
  #   groupId = id
  #
  #   unless groupId
  #     router.throw {status: 404, info: 'Group not found'}
  #
  #   Promise.all [
  #     Group.getById groupId
  #     Promise.map userIds, User.getById
  #   ]
  #   .then ([group, toUsers]) ->
  #     unless group
  #       router.throw {status: 404, info: 'Group not found'}
  #     if _.isEmpty toUsers
  #       router.throw {status: 404, info: 'User not found'}
  #
  #     hasPermission = Group.hasPermission group, user
  #     unless hasPermission
  #       router.throw {status: 400, info: 'You don\'t have permission'}
  #
  #     Promise.map toUsers, EmbedService.embed userDataEmbed
  #     .map (toUser) ->
  #       senderName = User.getDisplayName user
  #       groupInvitedIds = toUser.data.groupInvitedIds or []
  #       unreadGroupInvites = toUser.data.unreadGroupInvites or 0
  #       UserData.upsertByUserId toUser.id, {
  #         groupInvitedIds: _.uniq groupInvitedIds.concat [id]
  #         unreadGroupInvites: unreadGroupInvites + 1
  #       }
  #       PushNotificationService.send toUser, {
  #         title: 'New group invite'
            # TODO: if re-enabling, use titleObj, textObj
  #         text: "#{senderName} invited you to the group, #{group.name}"
  #         type: PushNotificationService.TYPES.GROUP
  #         url: "https://#{config.CLIENT_HOST}"
  #         data:
            # path: {
            #   key: 'groupById'
            #   params: {id: group.id, gameKey: 'clash-royale'}
            # }
  #       }
  #
  #     Group.updateById groupId,
  #       invitedIds: _.uniq group.invitedIds.concat(userIds)

  leaveById: ({id}, {user}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Group.getById groupId
    .then (group) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      Group.removeUser groupId, userId

  joinById: ({id}, {user, appKey}) ->
    groupId = id
    userId = user.id

    unless groupId
      router.throw {status: 404, info: 'Group not found'}

    Group.getById groupId
    .then (group) ->
      unless group
        router.throw {status: 404, info: 'Group not found'}

      if group.privacy is 'private' and group.invitedIds.indexOf(userId) is -1
        router.throw {status: 401, info: 'Not invited'}

      name = User.getDisplayName user

      if group.type isnt 'public'
        PushNotificationService.sendToGroupTopic(group, {
          titleObj:
            key: 'newGroupMember.title'
          textObj:
            key: 'newGroupMember.text'
            replacements: {name}
          type: PushNotificationService.TYPES.GROUP
          url: "https://#{config.CLIENT_HOST}"
          path:
            key: 'groupChat'
            params:
              id: group.id
              gameKey: config.DEFAULT_GAME_KEY
        }, {skipMe: true, meUserId: user.id}).catch -> null

      Group.addUser groupId, userId
      .then ->
        # TODO sub to group topics
        PushNotificationService.subscribeToPushTopic {
          userId: user.id
          groupId
          appKey
        }

        prefix = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY
        category = "#{prefix}:#{userId}"
        CacheService.deleteByCategory category

  sendNotificationById: ({title, description, pathKey, id}, {user}) ->
    groupId = id
    pathKey or= 'groupHome'

    # GroupUser.hasPermissionByGroupIdAndUser groupId, user, permissions
    Group.getById groupId
    .then (group) ->
      Group.hasPermission group, user, {level: 'admin'}
      .then (hasPermission) ->
        unless hasPermission
          router.throw status: 400, info: 'no permission'
        PushNotificationService.sendToGroupTopic group, {
          title: title
          text: description
          type: PushNotificationService.TYPES.NEWS
          data:
            path:
              key: pathKey
              params:
                groupId: groupId
        }

  getAllByUserId: ({language, user, userId, embed}) ->
    embed = _.map embed, (item) ->
      EmbedService.TYPES.GROUP[_.snakeCase(item).toUpperCase()]

    (if user
      Promise.resolve user
    else
      User.getById userId
    ).then (user) ->
      key = CacheService.PREFIXES.GROUP_GET_ALL + ':' + [
        user.id, 'mine_lite', language, embed.join(',')
      ].join(':')
      category = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY + ':' + user.id

      CacheService.preferCache key, ->
        GroupUser.getAllByUserId user.id, {preferCache: true}
        .map ({groupId}) -> groupId
        .then (groupIds) ->
          Group.getAllByIds groupIds
        .map EmbedService.embed {embed, user}
        .map Group.sanitize null
      , {
        expireSeconds: THIRTY_MINUTES_SECONDS
        category: category
      }

  getAll: ({filter, language, embed}, {user}) =>
    # TODO: rm mine part after 1/15/2017
    if filter is 'mine'
      return @getAllByUserId {filter, language, user, embed}
    else
      embed = _.map embed, (item) ->
        EmbedService.TYPES.GROUP[_.snakeCase(item).toUpperCase()]
      key = CacheService.PREFIXES.GROUP_GET_ALL + ':' + [
        user.id, filter, language, embed.join(',')
      ].join(':')
      category = CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY + ':' + user.id

      CacheService.preferCache key, ->
        Group.getAll {filter, language}
        .then (groups) ->
          if filter is 'public' and _.isEmpty groups
            Group.getAll {filter}
          else
            groups
        .map EmbedService.embed {embed, user}
        .map Group.sanitize null
      , {
        expireSeconds: THIRTY_MINUTES_SECONDS
        category: category
      }

  getAllChannelsById: ({id}, {user}) ->
    GroupUser.getByGroupIdAndUserId(
      id, user.id
    )
    .then EmbedService.embed {embed: [EmbedService.TYPES.GROUP_USER.ROLES]}
    .then (meGroupUser) ->
      Conversation.getAllByGroupId id
      .then (conversations) ->
        _.filter conversations, (conversation) ->
          GroupUser.hasPermission {
            meGroupUser
            permissions: [GroupUser.PERMISSIONS.MANAGE_CHANNEL]
            channelId: conversation.id
            me: user
          }

  getById: ({id}, {user}) ->
    Group.getById id
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Group.sanitize null

  getByKey: ({key}, {user}) ->
    Group.getByKey key
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Group.sanitize null

  getByGameKeyAndLanguage: ({gameKey, language}, {user}) ->
    Group.getByGameKeyAndLanguage gameKey, language, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Group.sanitize null

module.exports = new GroupCtrl()
