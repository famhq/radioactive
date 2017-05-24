_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

THREADS_TABLE = 'threads'
CREATOR_ID_INDEX = 'creatorId'
ATTACHMENT_IDS_INDEX = 'attachmentIds'
SCORE_INDEX = 'score'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

# update the scores for posts up until they're a month old
SCORE_UPDATE_TIME_RANGE_S = 3600 * 24 * 31

defaultThread = (thread) ->
  unless thread?
    return null

  _.defaults thread, {
    id: uuid.v4()
    creatorId: null
    groupId: null
    title: null
    body: null
    summary: null
    headerImage: null
    type: 'text'
    upvotes: 0
    downvotes: 0
    score: 0
    upvoteIds: []
    downvoteIds: []
    data: {}
    attachmentIds: []
    lastUpdateTime: new Date()
    addTime: new Date()
  }

class ThreadModel
  RETHINK_TABLES: [
    {
      name: THREADS_TABLE
      options: {}
      indexes: [
        {name: CREATOR_ID_INDEX}
        {name: SCORE_INDEX}
        {name: ATTACHMENT_IDS_INDEX}
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
    .orderBy {index: r.desc(SCORE_INDEX)}
    # .orderBy (thread) ->
    #   thread.merge({newScore: thread('upvotes').sub(thread('downvotes')).mul(r.expr(1).div(r.now().sub(thread('addTime')).div(3600 * 24 * 31)))})
    .limit limit
    .run()
    .map defaultThread

  getAllByAttachmentIds: (ids, {limit} = {}) ->
    limit ?= 10

    r.table THREADS_TABLE
    .getAll ids, {index: ATTACHMENT_IDS_INDEX}
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

  hasPermissionByIdAndUser: (id, user, {level} = {}) =>
    unless user
      return false

    @getById id
    .then (thread) =>
      @hasPermission thread, user, {level}

  hasPermission: (thread, user, {level} = {}) ->
    unless thread and user
      return false

    level ?= 'member'

    return switch level
      when 'admin'
      then thread.creatorId is user.id
      # member
      else thread.userIds?.indexOf(user.id) isnt -1

  sanitize: _.curry (requesterId, thread) ->
    _.pick thread, [
      'id'
      'creatorId'
      'creator'
      'type'
      'title'
      'summary'
      'headerImage'
      'body'
      'data'
      'deck'
      'comments'
      'commentCount'
      'score'
      'addTime'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new ThreadModel()
