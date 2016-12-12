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
    isPrivate: false
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
    level ?= 'member'
    @getById id
    .then (group) ->
      userId and group.userIds?.indexOf(userId) isnt -1

  getById: (id) ->
    r.table GROUPS_TABLE
    .get id
    .run()
    .then defaultGroup

  getAll: ({filter, limit, userId} = {}) ->
    limit ?= 10

    q = r.table GROUPS_TABLE

    console.log filter

    if filter is 'mine'
      q = q.getAll userId, {index: USER_IDS_INDEX}
    else if filter is 'open'
      q = q.filter r.row('isPrivate').default(false).eq(false)

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
      'userIds'
      'users'
      'embedded'
    ]

module.exports = new GroupModel()
