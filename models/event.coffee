_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'
USER_IDS_INDEX = 'userIds'
START_TIME_INDEX = 'startTime'

ONE_YEAR_SECONDS = 3600 * 24 * 365 * 10

defaultEvent = (event) ->
  unless event?
    return null

  _.defaults event, {
    id: uuid.v4()
    creatorId: null
    groupId: null
    name: ''
    description: ''
    startTime: null
    endTime: null
    maxUserCount: 50
    userIds: []
    noUserIds: []
    maybeUserIds: []
    invitedUserIds: []
    visibility: 'public'
    hasStarted: false
    password: null
    addTime: new Date()
    data:
      tournamentId: null
      minTrophies: null
      maxTrophies: null
  }

EVENTS_TABLE = 'events'

class EventModel
  RETHINK_TABLES: [
    {
      name: EVENTS_TABLE
      indexes: [
        {name: GROUP_ID_INDEX}
        {name: USER_IDS_INDEX, options: {multi: true}}
        {name: START_TIME_INDEX}
      ]
    }
  ]

  create: (event) ->
    event = defaultEvent event

    r.table EVENTS_TABLE
    .insert event
    .run()
    .then ->
      event

  getAll: ({filter, limit, user} = {}) ->
    limit ?= 50

    q = r.table EVENTS_TABLE

    if filter is 'mine'
      q = q.getAll user.id, {index: USER_IDS_INDEX}
          .filter r.row('startTime').gt(r.now())
          .orderBy r.asc('startTime')
    else
      q = q.between r.now(), r.now().add(ONE_YEAR_SECONDS), {
        index: START_TIME_INDEX
      }
      .filter ({visibility: 'public'})
      .orderBy r.asc START_TIME_INDEX

    q.limit limit
    .run()
    .map defaultEvent

  getAllByGroupId: (groupId) ->
    r.table EVENTS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()

  getAllStartingNow: ->
    r.table EVENTS_TABLE
    .between r.now().sub(60 * 5), r.now().add(3600), {index: START_TIME_INDEX}
    .filter r.row('hasStarted').default(false).ne(true)
    .run()

  getAllByIds: (ids) ->
    r.table EVENTS_TABLE
    .getAll ids, {index: GROUP_ID_INDEX}
    .run()

  getById: (id) ->
    r.table EVENTS_TABLE
    .get id
    .run()

  updateById: (id, diff) ->
    r.table EVENTS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table EVENTS_TABLE
    .get id
    .delete()
    .run()

  hasPermissionByIdAndUserId: (id, userId, {level} = {}) =>
    unless userId
      return false

    Promise.all [
      @getById id
      User.getById userId
    ]
    .then ([event, user]) =>
      @hasPermission event, user, {level}

  hasPermissionByIdAndUser: (id, user, {level} = {}) =>
    unless user
      return false

    @getById id
    .then (event) =>
      @hasPermission event, user, {level}

  hasPermission: (event, user, {level} = {}) ->
    unless event and user
      return false

    level ?= 'member'

    return switch level
      when 'admin'
      then event.creatorId is user.id
      # member
      else event.userIds?.indexOf(user.id) isnt -1

  sanitizePublic: _.curry (requesterId, eventData) ->
    _.pick eventData, [
      'id'
      'name'
      'creator'
      'creatorId'
      'description'
      'startTime'
      'endTime'
      'maxUserCount'
      'userIds'
      'users'
      'visibility'
      'data'
    ]

  sanitize: _.curry (requesterId, eventData) ->
    _.pick eventData, [
      'id'
      'name'
      'creator'
      'creatorId'
      'conversationId'
      'description'
      'startTime'
      'endTime'
      'maxUserCount'
      'password'
      'userIds'
      'users'
      'visibility'
      'data'
    ]

module.exports = new EventModel()
