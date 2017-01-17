_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'
CacheService = require '../services/cache'

defaultThreadComment = (threadComment) ->
  unless threadComment?
    return null

  _.defaults threadComment, {
    id: uuid.v4()
    userId: null
    time: new Date()
    body: ''
    toId: null
  }

THREAD_COMMENTS_TABLE = 'thread_comments'
TIME_INDEX = 'time'
USER_ID_INDEX = 'userId'
THREAD_ID_INDEX = 'threadId'
MAX_MESSAGES = 30

class ThreadCommentModel
  RETHINK_TABLES: [
    {
      name: THREAD_COMMENTS_TABLE
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

  create: (threadComment) ->
    threadComment = defaultThreadComment threadComment

    r.table THREAD_COMMENTS_TABLE
    .insert threadComment
    .run()
    .then ->
      threadComment

  updateById: (id, diff) ->
    r.table THREAD_COMMENTS_TABLE
    .get id
    .update diff
    .run()

  getAll: ->
    r.table THREAD_COMMENTS_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit MAX_MESSAGES
    .filter r.row('toId').default(null).eq(null)
    .run()
    .map defaultThreadComment

  getAllByThreadId: (threadId) ->
    r.table THREAD_COMMENTS_TABLE
    .getAll threadId, {index: THREAD_ID_INDEX}
    .orderBy r.asc(TIME_INDEX)
    .run()
    .map defaultThreadComment

  getFirstByThreadId: (threadId) ->
    r.table THREAD_COMMENTS_TABLE
    .getAll threadId, {index: THREAD_ID_INDEX}
    .orderBy r.asc(TIME_INDEX)
    .nth 0
    .default null
    .run()
    .then defaultThreadComment

  getById: (id) ->
    r.table THREAD_COMMENTS_TABLE
    .get id
    .run()
    .then defaultThreadComment

module.exports = new ThreadCommentModel()
