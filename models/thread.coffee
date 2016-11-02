_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

THREADS_TABLE = 'threads'
USER_ID_INDEX = 'userId'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

defaultThread = (thread) ->
  unless thread?
    return null

  _.assign {
    id: uuid.v4()
    userId: null
    title: null
    lastUpdateTime: new Date()
  }, thread

class ThreadModel
  RETHINK_TABLES: [
    {
      name: THREADS_TABLE
      options: {}
      indexes: [
        {name: USER_ID_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (thread) ->
    thread = defaultThread thread

    r.table THREADS_TABLE
    .insert thread
    .run()
    .then ->
      thread

  getById: (id) ->
    r.table THREADS_TABLE
    .get id
    .run()
    .then defaultThread

  getAll: ({limit} = {}) ->
    limit ?= 10

    r.table THREADS_TABLE
    .orderBy {index: r.desc(LAST_UPDATE_TIME_INDEX)}
    .limit limit
    .run()
    .map defaultThread

  updateById: (id, diff) ->
    r.table THREADS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table THREADS_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, thread) ->
    _.pick thread, [
      'id'
      'userId'
      'title'
      'firstMessage'
      'messages'
      'messageCount'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new ThreadModel()
