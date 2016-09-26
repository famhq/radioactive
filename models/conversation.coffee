_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

CONVERSATIONS_TABLE = 'conversations'
USER_ID_1_INDEX = 'userId1'
USER_ID_2_INDEX = 'userId2'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

defaultConversation = (conversation) ->
  unless conversation?
    return null

  _.assign {
    id: uuid.v4()
    userId1: null
    userId2: null
    lastUpdateTime: new Date()
  }, conversation

class ConversationModel
  RETHINK_TABLES: [
    {
      name: CONVERSATIONS_TABLE
      options: {}
      indexes: [
        {name: USER_ID_1_INDEX}
        {name: USER_ID_2_INDEX}
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

  getById: (id) ->
    r.table CONVERSATIONS_TABLE
    .get id
    .run()
    .then defaultConversation

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10

    r.union(
      r.table CONVERSATIONS_TABLE
      .getAll userId, {index: USER_ID_1_INDEX}
      .orderBy r.desc(LAST_UPDATE_TIME_INDEX)
      .limit limit

      r.table CONVERSATIONS_TABLE
      .getAll userId, {index: USER_ID_2_INDEX}
      .orderBy r.desc(LAST_UPDATE_TIME_INDEX)
      .limit limit
    )
    .distinct()
    .orderBy r.desc(LAST_UPDATE_TIME_INDEX)
    .limit limit
    .run()
    .map defaultConversation

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
      'userId1'
      'userId2'
      'messages'
    ]

module.exports = new ConversationModel()
