_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'

GROUPS_TABLE = 'groups'
USER_IDS_INDEX = 'userIds'

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
    mode: 'open' # open | private | inviteOnly
    type: 'general' # general | clan | star
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
      else group.userIds?.indexOf(user.id) isnt -1

  getById: (id) ->
    r.table GROUPS_TABLE
    .get id
    .run()
    .then defaultGroup

  getAll: ({filter, limit, user} = {}) ->
    limit ?= 10

    q = r.table GROUPS_TABLE

    if filter is 'mine'
      q = q.getAll user.id, {index: USER_IDS_INDEX}
    else if filter is 'invited'
      console.log user.data
      q = q.getAll r.args (user.data.groupInvitedIds or [])
    else if filter is 'open'
      q = q.filter r.row('mode').default('open').eq('open')

    q.orderBy r.desc r.row('userIds').count()
    .limit limit
    .run()
    .map defaultGroup

  updateById: (id, diff) ->
    r.table GROUPS_TABLE
    .get id
    .update diff
    .run()

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
