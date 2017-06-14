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
    creatorId: null
    parentId: null
    parentType: 'thread'
    body: ''
    upvotes: 0
    downvotes: 0
    time: new Date()

  }

THREAD_COMMENTS_TABLE = 'thread_comments'
TIME_INDEX = 'time'
CREATOR_ID_INDEX = 'creatorId'
PARENT_ID_PARENT_TYPE_TIME_INDEX = 'parentIdParentTypeTime'
MAX_MESSAGES = 30

class ThreadCommentModel
  RETHINK_TABLES: [
    {
      name: THREAD_COMMENTS_TABLE
      indexes: [
        {name: TIME_INDEX}
        {name: CREATOR_ID_INDEX}
        {name: PARENT_ID_PARENT_TYPE_TIME_INDEX, fn: (row) ->
          [row('parentId'), row('parentType'), row('time')]}
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

  getAllByParentIdAndParentType: (parentId, parentType) ->
    r.table THREAD_COMMENTS_TABLE
    .between(
      [parentId, parentType]
      [parentId + 'Z', parentType + 'Z']
      {index: PARENT_ID_PARENT_TYPE_TIME_INDEX}
    )
    .orderBy {index: r.desc(PARENT_ID_PARENT_TYPE_TIME_INDEX)}
    .limit 30
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
