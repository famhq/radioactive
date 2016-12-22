_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

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
    userIds: []
    invitedIds: []
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

  hasPermissionById: (id, userId, {level} = {}) =>
    unless userId
      return false

    @getById id
    .then (group) =>
      @hasPermission group, userId, {level}

  hasPermission: (group, userId, {level} = {}) ->
    unless userId
      return false

    level ?= 'member'

    return switch level
      when 'admin'
      then group.creatorId is userId
      # member
      else group.userIds?.indexOf(userId) isnt -1

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

  deleteById: (id) ->
    r.table GROUPS_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, group) ->
    _.pick group, [
      'id'
      'creatorId'
      'name'
      'description'
      'badgeId'
      'background'
      'mode'
      'userIds'
      'users'
      'embedded'
    ]

module.exports = new GroupModel()
