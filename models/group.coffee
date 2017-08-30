_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
User = require './user'
GroupUser = require './group_user'

GROUPS_TABLE = 'groups'
TYPE_LANGUAGE_INDEX = 'typeLanguage'

ONE_DAY_SECONDS = 3600 * 24

defaultGroup = (group) ->
  unless group?
    return null

  _.defaults group, {
    id: uuid.v4()
    creatorId: null
    name: null
    description: null
    badgeId: null
    background: null
    language: 'en'
    mode: 'open' # open | private | inviteOnly
    type: 'general' # public | general | clan | star
    gameIds: []
    clanIds: []
    starId: null
  }

class GroupModel
  RETHINK_TABLES: [
    {
      name: GROUPS_TABLE
      options: {}
      indexes: [
        {name: TYPE_LANGUAGE_INDEX, fn: (row) ->
          [row('type'), row('language')]}
      ]
    }
  ]

  create: (group) ->
    group = defaultGroup group

    r.table GROUPS_TABLE
    .insert group
    .run()
    .then ->
      group

  hasPermissionByIdAndUserId: (id, userId, {level} = {}) =>
    unless userId
      return false

    Promise.all [
      @getById id
      User.getById userId
    ]
    .then ([group, user]) =>
      @hasPermission group, user, {level}

  hasPermissionByIdAndUser: (id, user, {level} = {}) =>
    unless user
      return false

    @getById id
    .then (group) =>
      @hasPermission group, user, {level}

  hasPermission: (group, user, {level} = {}) ->
    unless group and user
      return false

    level ?= 'member'

    GroupUser.getAllByGroupId group.id
    .map ({userId}) -> userId
    .then (userIds) ->
      return switch level
        when 'admin'
        then group.creatorId is user.id
        # member
        else group.type is 'public' or userIds?.indexOf(user.id) isnt -1

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table GROUPS_TABLE
      .get id
      .merge (group) ->
        userIds = r.table('group_users').getAll(group('id'), {index: 'groupId'})
                  .map (groupUser) -> groupUser('userId')
                  .coerceTo('array')
        {userIds}
      .run()
      .then defaultGroup

    if preferCache
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  getAllByIds: (ids, {limit} = {}) ->
    limit ?= 10

    r.table GROUPS_TABLE
    .getAll r.args _.filter(ids)
    .limit limit
    .merge (group) ->
      userIds = r.table('group_users').getAll(group('id'), {index: 'groupId'})
                .map (groupUser) -> groupUser('userId')
                .coerceTo('array')
      {userIds}
    .run()

  getAll: ({filter, language, limit, user} = {}) ->
    limit ?= 10

    q = r.table GROUPS_TABLE

    if filter is 'public' and language
      q = q.getAll ['public', language], {index: TYPE_LANGUAGE_INDEX}
    # else if filter is 'invited'
    #   q = q.getAll r.args (user.data.groupInvitedIds or [])
    else if filter is 'public'
      q = q.getAll ['public'], {index: TYPE_LANGUAGE_INDEX}

    # q.orderBy r.desc r.row('userIds').count()
    q.limit limit
    .merge (group) ->
      userIds = r.table('group_users').getAll(group('id'), {index: 'groupId'})
                .map (groupUser) -> groupUser('userId')
                .coerceTo('array')
      {userIds}
    .run()
    .map defaultGroup

  updateById: (id, diff) ->
    r.table GROUPS_TABLE
    .get id
    .update diff
    .run()
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{id}"
      CacheService.deleteByKey key
      null

  addUser: (groupId, userId) ->
    console.log 'add user', groupId, userId
    GroupUser.create {groupId, userId}
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{groupId}"
      CacheService.deleteByKey key

  removeUser: (groupId, userId) ->
    GroupUser.deleteByGroupIdAndUserId groupId, userId
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{groupId}"
      CacheService.deleteByKey key

  deleteById: (id) ->
    r.table GROUPS_TABLE
    .get id
    .delete()
    .run()
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{id}"
      CacheService.deleteByKey key

  sanitizePublic: _.curry (requesterId, group) ->
    sanitizedGroup = _.pick group, [
      'id'
      'creatorId'
      'name'
      'description'
      'clan'
      'badgeId'
      'background'
      'mode'
      'type'
      'userIds'
      'starId'
      'star'
      'conversations'
      'embedded'
    ]
    sanitizedGroup

  sanitize: _.curry (requesterId, group) ->
    sanitizedGroup = _.pick group, [
      'id'
      'creatorId'
      'name'
      'description'
      'clan'
      'badgeId'
      'background'
      'mode'
      'type'
      'userIds'
      'starId'
      'star'
      'password'
      'conversations'
      'embedded'
    ]
    sanitizedGroup

module.exports = new GroupModel()
