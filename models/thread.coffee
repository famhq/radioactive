_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

THREADS_TABLE = 'threads'
CREATOR_ID_INDEX = 'creatorId'
ATTACHMENT_IDS_INDEX = 'attachmentIds'
SCORE_INDEX = 'score'
CATEGORY_SCORE_INDEX = 'categoryScore'
ADD_TIME_INDEX = 'addTime'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

# update the scores for posts up until they're a week old
SCORE_UPDATE_TIME_RANGE_S = 3600 * 24 * 7

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
    translations: {}
    headerImage: null
    type: 'text'
    category: 'general'
    upvotes: 0
    downvotes: 0
    score: 0
    data: {}
    attachmentIds: []
    attachments: []
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
        {name: CATEGORY_SCORE_INDEX, fn: (row) ->
          [row('category'), row('score')]}
        {name: ATTACHMENT_IDS_INDEX}
        {name: ADD_TIME_INDEX}
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

  updateScores: =>
    r.table THREADS_TABLE
    # .between ['general'], ['generalZ'], {index: 'categoryScore'}
    .between r.now().sub(90), r.now(), {
      index: LAST_UPDATE_TIME_INDEX
    }
    .run()
    .then (threads) =>
      Promise.map threads, (thread) =>
        # https://medium.com/hacking-and-gonzo/how-reddit-ranking-algorithms-work-ef111e33d0d9
        # ^ simplification in comments
        rawScore = thread.upvotes - thread.downvotes
        order = Math.log10(Math.max(Math.abs(rawScore), 1))
        sign = if rawScore > 0 then 1 else if rawScore < 0 then -1 else 0
        postAgeHours = (Date.now() - thread.addTime.getTime()) / (3600 * 1000)
        score = sign * order / Math.pow(2, postAgeHours / 3.76)
        score = Math.round(score * 1000000)
        @updateById thread.id, {score}
      , {concurrency: 50}


  getAll: ({category, limit, sort} = {}) ->
    limit ?= 20

    if category
      q = r.table THREADS_TABLE
      .between [category + '!'], [category + '~'], {
        index: CATEGORY_SCORE_INDEX
      }
      .orderBy {index: r.desc(CATEGORY_SCORE_INDEX)}
    else
      q = r.table THREADS_TABLE
      if sort is 'new'
        q = q.orderBy {index: r.desc(ADD_TIME_INDEX)}
      else
        q = q.orderBy {index: r.desc(SCORE_INDEX)}
    q.limit limit
    .filter r.row('score').gt -2
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
    diff = _.defaults {lastUpdateTime: new Date()}, diff
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
      'attachments'
      'myVote'
      'score'
      'upvotes'
      'downvotes'
      'addTime'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new ThreadModel()
