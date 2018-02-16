_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
User = require './user'
GroupUser = require './group_user'
config = require '../config'

GROUPS_TABLE = 'groups'
TYPE_LANGUAGE_INDEX = 'typeLanguage'
KEY_INDEX = 'key'

ONE_DAY_SECONDS = 3600 * 24
ONE_HOUR_SECONDS = 3600

defaultGroup = (group) ->
  unless group?
    return null

  _.defaults group, {
    id: uuid.v4()
    creatorId: null
    name: null
    description: null
    key: null
    badgeId: null
    badge: null
    background: null
    privacy: 'open' # open | private | inviteOnly
    type: 'general' # public | general | clan | star

    # TODO: index on this when migrating to scylla
    # need to grab group by gameKey and language
    gameKeys: []
    language: 'en'

    clanIds: []
    starId: null
  }

class GroupModel
  RETHINK_TABLES: [
    {
      name: GROUPS_TABLE
      options: {}
      indexes: [
        {name: KEY_INDEX}
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
      User.getById userId, {preferCache: true}
    ]
    .then ([group, user]) =>
      @hasPermission group, user, {level}

  hasPermissionByIdAndUser: (id, user, {level} = {}) =>
    unless user
      return false

    @getById id
    .then (group) =>
      @hasPermission group, user, {level}

  # TODO: phase out for groupUser.hasPermission
  hasPermission: (group, user, {level} = {}) ->
    unless group and user
      return false

    level ?= 'member'

    if level is 'admin'
      return Promise.resolve(
        group.creatorId is user.id or user.username is 'austin'
      )

    # public groups have waaaaaaaaaaay to many users
    if group.type is 'public'
      return Promise.resolve true

    GroupUser.getAllByGroupId group.id
    .map ({userId}) -> "#{userId}"
    .then (userIds) ->
      userIds and userIds.indexOf(user.id) isnt -1

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table GROUPS_TABLE
      .get id
      .run()
      .catch (err) ->
        console.log 'rethink err', id, err
        throw err
      .then defaultGroup

    if preferCache
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  getByKey: (key, {preferCache} = {}) ->
    get = ->
      r.table GROUPS_TABLE
      .getAll key, {index: KEY_INDEX}
      .nth 0
      .default null
      .run()
      .then defaultGroup

    if preferCache
      key = "#{CacheService.PREFIXES.GROUP_KEY}:#{key}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  getAllByIds: (ids, {limit} = {}) ->
    limit ?= 50

    r.table GROUPS_TABLE
    # convert from scylla uuid type
    .getAll r.args _.map(_.filter(ids), (id) -> "#{id}")
    .limit limit
    # .merge (group) ->
    #   userIds = r.table('group_users').getAll(group('id'), {index: 'groupId'})
    #             .map (groupUser) -> groupUser('userId')
    #             .coerceTo('array')
    #   {userIds}
    .run()

  getAll: ({filter, language, limit} = {}) ->
    limit ?= 10

    q = r.table GROUPS_TABLE

    if filter is 'public' and language
      q = q.getAll ['public', language], {index: TYPE_LANGUAGE_INDEX}
    else if filter is 'public'
      q = q.getAll ['public'], {index: TYPE_LANGUAGE_INDEX}

    # q.orderBy r.desc r.row('userIds').count()
    q.limit limit
    # .merge (group) ->
    #   userIds = r.table('group_users').getAll(group('id'), {index: 'groupId'})
    #             .map (groupUser) -> groupUser('userId')
    #             .coerceTo('array')
    #   {userIds}
    .run()
    .map defaultGroup

  getByGameKeyAndLanguage: (gameKey, language, {preferCache} = {}) ->
    get = =>
      r.table GROUPS_TABLE
      .getAll ['public', language], {index: TYPE_LANGUAGE_INDEX}
      .then (groups) =>
        group = _.find groups, ({gameKeys}) ->
          gameKeys and gameKeys.indexOf(gameKey) isnt -1
        if group
          return group
        else
          @getById config.GROUPS.CLASH_ROYALE_EN
    if preferCache
      prefix = CacheService.PREFIXES.GROUP_GAME_KEY_LANGUAGE
      key = "#{prefix}:#{gameKey}:#{language}"
      CacheService.preferCache key, get, {expireSeconds: ONE_HOUR_SECONDS}
    else
      get()

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
    GroupUser.create {groupId, userId}
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{groupId}"
      CacheService.deleteByKey key
      category = "#{CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY}:#{userId}"
      CacheService.deleteByCategory category

  removeUser: (groupId, userId) ->
    GroupUser.deleteByGroupIdAndUserId groupId, userId
    .tap ->
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{groupId}"
      CacheService.deleteByKey key
      category = "#{CacheService.PREFIXES.GROUP_GET_ALL_CATEGORY}:#{userId}"
      CacheService.deleteByCategory category

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
      'key'
      'creatorId'
      'name'
      'description'
      'clan'
      'badgeId'
      'badge'
      'background'
      'mode'
      'gameKeys'
      'type'
      'userIds'
      'userCount'
      'starId'
      'star'
      'conversations'
      'meGroupUser'
      'embedded'
    ]
    sanitizedGroup

  sanitize: _.curry (requesterId, group) ->
    sanitizedGroup = _.pick group, [
      'id'
      'key'
      'creatorId'
      'name'
      'description'
      'clan'
      'badgeId'
      'badge'
      'background'
      'mode'
      'gameKeys'
      'type'
      'userIds'
      'userCount'
      'starId'
      'star'
      'password'
      'conversations'
      'meGroupUser'
      'embedded'
    ]
    sanitizedGroup

module.exports = new GroupModel()
