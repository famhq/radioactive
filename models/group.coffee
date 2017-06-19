_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
User = require './user'

GROUPS_TABLE = 'groups'
USER_IDS_INDEX = 'userIds'
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
    userIds: []
    invitedIds: []
    clanIds: []
  }

class GroupModel
  RETHINK_TABLES: [
    {
      name: GROUPS_TABLE
      options: {}
      indexes: [
        {name: USER_IDS_INDEX, options: {multi: true}}
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

    return switch level
      when 'admin'
      then group.creatorId is user.id
      # member
      else group.type is 'public' or group.userIds?.indexOf(user.id) isnt -1

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table GROUPS_TABLE
      .get id
      .run()
      .then defaultGroup

    if preferCache
      key = "#{CacheService.PREFIXES.GROUP_ID}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()


  getAll: ({filter, language, limit, user} = {}) ->
    limit ?= 10

    q = r.table GROUPS_TABLE

    if filter is 'mine'
      q = q.getAll user.id, {index: USER_IDS_INDEX}
    else if filter is 'invited'
      q = q.getAll r.args (user.data.groupInvitedIds or [])
    else if filter is 'open'
      q = q.filter r.row('mode').default('open').eq('open')
    else if filter is 'public' and language
      q = q.getAll ['public', language], {index: TYPE_LANGUAGE_INDEX}
    else if filter is 'public'
      q = q.getAll ['public'], {index: TYPE_LANGUAGE_INDEX}

    q.orderBy r.desc r.row('userIds').count()
    .limit limit
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

  addUser: (id, userId) =>
    @updateById id, {
      userIds: r.row('userIds').append(userId).distinct()
    }

  deleteById: (id) ->
    r.table GROUPS_TABLE
    .get id
    .delete()
    .run()

  sanitizePublic: _.curry (requesterId, group) ->
    sanitizedGroup = _.pick group, [
      'id'
      'creatorId'
      'name'
      'description'
      'badgeId'
      'background'
      'mode'
      'type'
      'userIds'
      'users'
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
      'badgeId'
      'background'
      'mode'
      'type'
      'userIds'
      'users'
      'password'
      'conversations'
      'embedded'
    ]
    sanitizedGroup

module.exports = new GroupModel()
