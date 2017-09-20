_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

THREADS_TABLE = 'threads'
CREATOR_ID_INDEX = 'creatorId'
ATTACHMENT_IDS_INDEX = 'attachmentIds'
SCORE_INDEX = 'score'
CATEGORY_SCORE_INDEX = 'categoryScore'
CATEGORY_ADD_TIME_INDEX = 'categoryAddTime'
ADD_TIME_INDEX = 'addTime'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'
IS_SCORE_STALE_INDEX = 'isScoreStale'

# update the scores for posts up until they're 10 days old
SCORE_UPDATE_TIME_RANGE_S = 3600 * 24 * 10

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
    isScoreStale: false
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
        {name: CATEGORY_ADD_TIME_INDEX, fn: (row) ->
          [row('category'), row('addTime')]}
        {name: ATTACHMENT_IDS_INDEX}
        {name: IS_SCORE_STALE_INDEX}
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

  updateScores: (type = 'stale') =>
    # FIXME: also need to factor in time when grabbing threads. Even without
    # an upvote, threads need to eventually be updated for time increasing.
    # maybe do it by addTime up until 3 days, and run not as freq?

    (if type is 'stale'
      r.table THREADS_TABLE
      # .between ['general'], ['generalZ'], {index: 'categoryScore'}
      .getAll true, {index: IS_SCORE_STALE_INDEX}
      .run()
    else
      r.table THREADS_TABLE
      .between r.now().sub(3600 * 24 * 3), r.now(), {index: ADD_TIME_INDEX}
      .run()
    )
    .then (threads) =>
      console.log 'updating threads', type, threads?.length
      Promise.map threads, (thread) =>
        # https://medium.com/hacking-and-gonzo/how-reddit-ranking-algorithms-work-ef111e33d0d9
        # ^ simplification in comments

        # people heavily downvote, so offset it a bit...
        rawScore = Math.abs(thread.upvotes * 1.5 - thread.downvotes)
        if thread.category is 'news'
          rawScore = Math.max(10, rawScore)
          rawScore *= 5
        order = Math.log10(Math.max(Math.abs(rawScore), 1))
        sign = if rawScore > 0 then 1 else if rawScore < 0 then -1 else 0
        postAgeHours = (Date.now() - thread.addTime.getTime()) / (3600 * 1000)
        score = sign * order / Math.pow(2, postAgeHours / 3.76)
        score = Math.round(score * 1000000)
        @updateById thread.id, {score, isScoreStale: false}
      , {concurrency: 50}


  getAll: ({categories, language, sort, skip, limit} = {}) ->
    limit ?= 20
    skip ?= 0

    if skip + limit > 20000 # would be slow in rethink. 1000 pages is plenty
      throw new Error 'no results found'

    # https://github.com/rethinkdb/rethinkdb/issues/4325
    if not _.isEmpty categories
      index = if sort is 'new' \
              then CATEGORY_ADD_TIME_INDEX
              else CATEGORY_SCORE_INDEX

      q = r.expr []
      _.map categories, (category) ->
        q = q.union(
          r.table THREADS_TABLE
          .between [category], [category + 'Z'], {
            index: index
          }
          .orderBy({index: r.desc(index)})
          .limit skip + limit
          # , {interleave: 'time'} # this crashes rethinkdb...
        )
        # re-sort after union
        q = q.orderBy r.desc if sort is 'new' then 'time' else 'score'
    else
      q = r.table THREADS_TABLE
      if sort is 'new'
        q = q.orderBy {index: r.desc(ADD_TIME_INDEX)}
      else
        q = q.orderBy {index: r.desc(SCORE_INDEX)}

    q = q.skip skip
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
    diff = _.defaults diff, {lastUpdateTime: new Date(), isScoreStale: true}

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
      return Promise.resolve false

    @getById id
    .then (thread) =>
      @hasPermission thread, user, {level}

  hasPermission: (thread, user, {level} = {}) ->
    unless thread and user
      return false

    return thread.creatorId is user.id

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
      'playerDeck'
      'category'
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
