_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
Group = require './group'
Event = require './event'

CONVERSATIONS_TABLE = 'conversations'
USER_IDS_INDEX = 'userIds'
GROUP_ID_INDEX = 'groupId'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'
ONE_DAY_S = 3600 * 24

defaultConversation = (conversation) ->
  unless conversation?
    return null

  _.defaults conversation, {
    id: uuid.v4()
    userIds: []
    groupId: null
    type: 'pm' # pm | channel | event
    name: null
    description: null
    userData: {}
    # null used to determine if message has been sent in convo
    lastUpdateTime: null # new Date()
  }

class ConversationModel
  RETHINK_TABLES: [
    {
      name: CONVERSATIONS_TABLE
      options: {}
      indexes: [
        {name: USER_IDS_INDEX, options: {multi: true}}
        {name: GROUP_ID_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (conversation) ->
    conversation = defaultConversation conversation

    r.table CONVERSATIONS_TABLE
    .insert conversation
    .run()
    .then ->
      conversation

  getById: (id, {preferCache} = {}) ->
    preferCache ?= true
    get = ->
      r.table CONVERSATIONS_TABLE
      .get id
      .run()
      .then defaultConversation

    if preferCache
      prefix = CacheService.PREFIXES.CONVERSATION_ID
      key = "#{prefix}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_S}
    else
      get()

  getByGroupIdAndName: (groupId, name) ->
    r.table CONVERSATIONS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .filter {name}
    .nth 0
    .default null
    .run()
    .then defaultConversation

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10

    r.table CONVERSATIONS_TABLE
    .getAll userId, {index: USER_IDS_INDEX}
    .filter(
      r.row('type').eq('pm')
      .and r.row('lastUpdateTime').default(null).ne(null)
    )
    .orderBy r.desc(LAST_UPDATE_TIME_INDEX)
    .limit limit
    .run()
    .map defaultConversation

  getAllByGroupId: (groupId) ->
    r.table CONVERSATIONS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .orderBy r.asc LAST_UPDATE_TIME_INDEX
    .run()
    .map defaultConversation

  getByUserIds: (checkUserIds, {limit} = {}) ->
    q = r.table CONVERSATIONS_TABLE
    .getAll checkUserIds[0], {index: USER_IDS_INDEX}
    .filter (conversation) ->
      conversation('type').eq('pm').and(
        r.expr(checkUserIds).filter (userId) ->
          conversation('userIds').contains(userId)
        .count()
        .eq(r.expr(checkUserIds).count())
      )

    .nth 0
    .default null
    .run()
    .then defaultConversation

  hasPermission: (conversation, userId) ->
    if conversation.groupId
      Group.hasPermissionByIdAndUserId conversation.groupId, userId
    else if conversation.eventId
      Event.getById conversation.eventId
      .then (event) ->
        event and event.userIds.indexOf(userId) isnt -1
    else
      Promise.resolve userId and conversation.userIds.indexOf(userId) isnt -1

  markRead: ({id, userIds}, userId) =>
    @updateById id, {
      userData:
        "#{userId}": {isRead: true}
    }

  updateById: (id, diff) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, conversation) ->
    _.pick conversation, [
      'id'
      'userIds'
      'userData'
      'users'
      'groupId'
      'name'
      'description'
      'lastUpdateTime'
      'lastMessage'
      'embedded'
    ]

module.exports = new ConversationModel()
