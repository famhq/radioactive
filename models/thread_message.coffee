_ = require 'lodash'
Promise = require 'bluebird'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'
CacheService = require '../services/cache'

defaultThreadMessage = (threadMessage) ->
  unless threadMessage?
    return null

  _.defaults threadMessage, {
    id: uuid.v4()
    userId: null
    time: new Date()
    body: ''
    toId: null
  }

THREAD_MESSAGES_TABLE = 'thread_messages'
TIME_INDEX = 'time'
USER_ID_INDEX = 'userId'
THREAD_ID_INDEX = 'threadId'
MAX_MESSAGES = 30

class ThreadMessageModel
  RETHINK_TABLES: [
    {
      name: THREAD_MESSAGES_TABLE
      indexes: [
        {
          name: TIME_INDEX
        }
        {
          name: USER_ID_INDEX
        }
        {
          name: THREAD_ID_INDEX
        }
      ]
    }
  ]

  create: (threadMessage) ->
    threadMessage = defaultThreadMessage threadMessage

    r.table THREAD_MESSAGES_TABLE
    .insert threadMessage
    .run()
    .then ->
      threadMessage

  getAll: ->
    r.table THREAD_MESSAGES_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit MAX_MESSAGES
    .filter r.row('toId').default(null).eq(null)
    .run()
    .map defaultThreadMessage

  getAllByThreadId: (threadId) ->
    r.table THREAD_MESSAGES_TABLE
    .getAll threadId, {index: THREAD_ID_INDEX}
    .orderBy r.desc(TIME_INDEX)
    .run()
    .map defaultThreadMessage

  getFirstByThreadId: (threadId) ->
    r.table THREAD_MESSAGES_TABLE
    .getAll threadId, {index: THREAD_ID_INDEX}
    .orderBy r.asc(TIME_INDEX)
    .nth 0
    .default null
    .run()
    .then defaultThreadMessage

  getById: (id) ->
    r.table THREAD_MESSAGES_TABLE
    .get id
    .run()
    .then defaultThreadMessage

module.exports = new ThreadMessageModel()
