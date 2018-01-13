_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

# update the scores for posts up until they're 10 days old
SCORE_UPDATE_TIME_RANGE_S = 3600 * 24 * 10

defaultThread = (thread) ->
  unless thread?
    return null

  thread.data?.lastUpdateTime = new Date()
  thread.data = JSON.stringify thread.data

  _.defaults thread, {
    id: cknex.getTimeUuid()
    creatorId: null
    category: 'general'
    data: {}
    timeBucket: 'MONTH-' + moment().format 'YYYY-MM'
  }

defaultThreadOutput = (thread) ->
  unless thread?.id
    return null

  thread.data = try
    JSON.parse thread.data
  catch error
    {}

  thread.time = thread.id.getDate()

  thread


tables = [
  {
    name: 'threads_counter_by_id'
    fields:
      id: 'timeuuid'
      upvotes: 'counter'
      downvotes: 'counter'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
  {
    name: 'threads_recent'
    keyspace: 'starfire'
    fields:
      partition: 'int' # always 1
      id: 'timeuuid'
      groupId: 'uuid'
      category: 'text'
    primaryKey:
      partitionKey: ['partition']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'threads_by_groupId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      creatorId: 'uuid'
      category: 'text'
      data: 'text'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['groupId', 'timeBucket']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'threads_by_groupId_and_category'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      creatorId: 'uuid'
      category: 'text'
      data: 'text'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['groupId', 'category', 'timeBucket']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'threads_by_creatorId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      creatorId: 'uuid'
      category: 'text'
      data: 'text' # title, body, type, attachmentIds/attachments?, lastUpdateTime
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['creatorId'] # may want to restructure with timeBucket
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'threads_by_id'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      groupId: 'uuid'
      creatorId: 'uuid'
      category: 'text'
      data: 'text' # title, body, type, attachmentIds/attachments?
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['id']
  }
]

class ThreadModel
  SCYLLA_TABLES: tables

  upsert: (thread) ->
    thread = defaultThread thread

    Promise.all [
      # only use for updating scores when post isnt set as stale
      if thread.category is 'clan'
        Promise.resolve null
      else
        Promise.resolve null
        cknex().insert {
          partition: 1
          id: thread.id
          groupId: thread.groupId
          category: thread.category
        }
        .into 'threads_recent'
        .usingTTL SCORE_UPDATE_TIME_RANGE_S
        .run()

      if thread.category is 'clan'
        Promise.resolve null
      else
        cknex().update 'threads_by_groupId'
        .set _.omit thread, ['groupId', 'timeBucket', 'id']
        .where 'groupId', '=', thread.groupId
        .andWhere 'timeBucket', '=', thread.timeBucket
        .andWhere 'id', '=', thread.id
        .run()

      cknex().update 'threads_by_groupId_and_category'
      .set _.omit thread, ['groupId', 'category', 'timeBucket', 'id']
      .where 'groupId', '=', thread.groupId
      .andWhere 'category', '=', thread.category
      .andWhere 'timeBucket', '=', thread.timeBucket
      .andWhere 'id', '=', thread.id
      .run()

      cknex().update 'threads_by_creatorId'
      .set _.omit thread, ['creatorId', 'timeBucket', 'id']
      .where 'creatorId', '=', thread.creatorId
      .andWhere 'id', '=', thread.id
      .run()

      cknex().update 'threads_by_id'
      .set _.omit thread, ['id']
      .where 'id', '=', thread.id
      .run()
    ]
    .then ->
      thread

  getById: (id) =>
    Promise.all [
      cknex().select '*'
      .from 'threads_by_id'
      .where 'id', '=', id
      .run {isSingle: true}

      @getCounterById id
    ]
    .then ([thread, threadCounter]) ->
      threadCounter or= {upvotes: 0, downvotes: 0}
      _.defaults thread, threadCounter
    .then defaultThreadOutput

  getStale: ->
    CacheService.arrayGetAll CacheService.KEYS.STALE_THREAD_IDS
    .map (value) ->
      arr = value.split '|'
      {groupId: arr[0], category: arr[1], id: arr[2]}

  setStaleByGroupIdAndCategoryAndId: (groupId, category, id) ->
    key = CacheService.KEYS.STALE_THREAD_IDS
    CacheService.arrayAppend key, "#{groupId}|#{category}|#{id}"

  getAllNewish: (limit) ->
    q = cknex().select '*'
    .from 'threads_recent'
    .where 'partition', '=', 1

    if limit
      q.limit limit

    q.run()

  getCounterById: (id) ->
    cknex().select '*'
    .from 'threads_counter_by_id'
    .where 'id', '=', id
    .run {isSingle: true}

  updateScores: (type, groupIds) =>
    # FIXME: also need to factor in time when grabbing threads. Even without
    # an upvote, threads need to eventually be updated for time increasing.
    # maybe do it by addTime up until 3 days, and run not as freq?

    (if type is 'time' then @getAllNewish() else @getStale())
    .map ({id, groupId, category}) =>
      @getCounterById id
      .then (threadCount) ->
        threadCount or= {upvotes: 0, downvotes: 0}
        _.defaults {id, groupId, category}, threadCount
    .then (threadCounts) =>
      console.log 'updating threads', type, threadCounts?.length
      Promise.map threadCounts, (thread) =>
        # https://medium.com/hacking-and-gonzo/how-reddit-ranking-algorithms-work-ef111e33d0d9
        # ^ simplification in comments

        unless thread.id
          return

        id = if typeof thread.id is 'string' \
                   then cknex.getTimeUuidFromString thread.id
                   else thread.id
        addTime = id.getDate()

        # people heavily downvote, so offset it a bit...
        thread.upvotes += 1 # for the initial user vote
        rawScore = Math.abs(thread.upvotes * 1.5 - thread.downvotes)
        order = Math.log10(Math.max(Math.abs(rawScore), 1))
        sign = if rawScore > 0 then 1 else if rawScore < 0 then -1 else 0
        postAgeHours = (Date.now() - addTime.getTime()) / (3600 * 1000)
        if "#{thread.id}" is 'fcb35890-f40e-11e7-9af5-920aa1303bef' or "#{thread.id}" is '90c06cb0-86ce-4ed6-9257-f36633db59c2'
          postAgeHours = 1
        score = sign * order / Math.pow(2, postAgeHours / 12)#3.76)
        score = Math.round(score * 1000000)
        @setScoreByThread thread, score
      , {concurrency: 50}

  setScoreByThread: ({groupId, category, id}, score) ->
    groupAllPrefix = CacheService.STATIC_PREFIXES
                    .THREAD_GROUP_LEADERBOARD_ALL
    groupAllKey = "#{groupAllPrefix}:#{groupId}"
    CacheService.leaderboardUpdate groupAllKey, id, score

    groupCategoryPrefix = CacheService.STATIC_PREFIXES
                          .THREAD_GROUP_LEADERBOARD_BY_CATEGORY
    groupCategoryKey = "#{groupCategoryPrefix}:#{groupId}:#{category}"
    CacheService.leaderboardUpdate groupCategoryKey, id, score

  getAll: (options = {}) =>
    {category, language, groupId, sort, skip, maxTimeUuid, limit} = options
    limit ?= 20
    skip ?= 0
    (if sort is 'new'
      @getAllTimeSorted {category, language, groupId, maxTimeUuid, limit}
    else
      @getAllScoreSorted {category, language, groupId, skip, limit})
    .map (thread) =>
      unless thread
        return
      @getCounterById thread.id
      .then (threadCounter) ->
        threadCounter or= {upvotes: 0, downvotes: 0}
        _.defaults thread, threadCounter
    .map defaultThreadOutput

  # need skip for redis-style (score), maxTimeUuid for scylla-style (time)
  getAllScoreSorted: ({category, language, groupId, skip, limit} = {}) ->
    (if category
      prefix = CacheService.STATIC_PREFIXES.THREAD_GROUP_LEADERBOARD_BY_CATEGORY
      CacheService.leaderboardGet "#{prefix}:#{groupId}:#{category}", {
        skip, limit
      }
    else
      prefix = CacheService.STATIC_PREFIXES.THREAD_GROUP_LEADERBOARD_ALL
      CacheService.leaderboardGet "#{prefix}:#{groupId}", {skip, limit}
    )
    .then (results) ->
      console.log 'got scores', results.length
      Promise.map _.chunk(results, 2), ([threadId, score]) ->
        cknex().select '*'
        .from 'threads_by_id'
        .where 'id', '=', threadId
        .run {isSingle: true}
      .filter (thread) ->
        thread

  getAllTimeSorted: ({category, language, groupId, maxTimeUuid, limit} = {}) ->
    get = (timeBucket) ->
      if category
        q = cknex().select '*'
        .from 'threads_by_groupId_and_category'
        .where 'groupId', '=', groupId
        .andWhere 'category', '=', category
        .andWhere 'timeBucket', '=', timeBucket
      else
        q = cknex().select '*'
        .from 'threads_by_groupId'
        .where 'groupId', '=', groupId
        .andWhere 'timeBucket', '=', timeBucket

      if maxTimeUuid
        q = q.andWhere 'id', '<', maxTimeUuid

      q.limit limit
      .run()

    maxTime = if maxTimeUuid \
              then cknex.getTimeUuidFromString(maxTimeUuid).getDate()
              else undefined

    get 'MONTH-' + moment(maxTime).format 'YYYY-MM'
    .then (results) ->
      if results.length < limit
        get 'MONTH-' + moment(maxTime).subtract(1, 'month').format 'YYYY-MM'
        .then (moreResults) ->
          if _.isEmpty moreResults
            results
          else
            results.concat moreResults
      else
        results

  incrementById: (id, diff) ->
    q = cknex().update 'threads_counter_by_id'
    _.forEach diff, (amount, key) ->
      q = q.increment key, amount
    q.where 'id', '=', id
    .run()

  deleteByThread: (thread) ->
    groupAllPrefix = CacheService.STATIC_PREFIXES
                    .THREAD_GROUP_LEADERBOARD_ALL
    groupAllKey = "#{groupAllPrefix}:#{thread.groupId}"

    groupCategoryPrefix = CacheService.STATIC_PREFIXES
                          .THREAD_GROUP_LEADERBOARD_BY_CATEGORY
    groupCategoryKey = "#{groupCategoryPrefix}:" +
                        "#{thread.groupId}:#{thread.category}"

    Promise.all [
      CacheService.leaderboardDelete groupAllKey, thread.id
      CacheService.leaderboardDelete groupCategoryKey, thread.id

      cknex().delete()
      .from 'threads_recent'
      .where 'partition', '=', 1
      .andWhere 'id', '=', thread.id
      .run()

      cknex().delete()
      .from 'threads_by_groupId'
      .where 'groupId', '=', thread.groupId
      .andWhere 'timeBucket', '=', thread.timeBucket
      .andWhere 'id', '=', thread.id
      .run()

      cknex().delete()
      .from 'threads_by_groupId_and_category'
      .where 'groupId', '=', thread.groupId
      .andWhere 'category', '=', thread.category
      .andWhere 'timeBucket', '=', thread.timeBucket
      .andWhere 'id', '=', thread.id
      .run()

      cknex().delete()
      .from 'threads_by_creatorId'
      .where 'creatorId', '=', thread.creatorId
      .andWhere 'id', '=', thread.id
      .run()

      cknex().delete()
      .from 'threads_by_id'
      .where 'id', '=', thread.id
      .run()

      cknex().delete()
      .from 'threads_counter_by_id'
      .where 'id', '=', thread.id
      .run()
    ]

  deleteById: (id) =>
    @getById id
    .then @deleteByThread

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

  # migrateGroupId: =>
  #   # threadIds = ['7ebd10e0-f553-11e7-a8f6-696b99b549b2']
  #   threadIds = [
  #     '7ebd10e0-f553-11e7-a8f6-696b99b549b2'
  #     'e08b3450-f544-11e7-9c81-cc7e056d6806'
  #     '7e1898b0-f541-11e7-975a-fe08eb96de40'
  #     '67a12470-f542-11e7-83d8-fdb9b3e7a06f'
  #     '65baec00-f505-11e7-843a-e517c5b8b8a7'
  #   ]
  #   Promise.map threadIds, (id) =>
  #     cknex().select '*'
  #     .from 'threads_by_id'
  #     .where 'id', '=', id
  #     .run {isSingle: true}
  #     .then defaultThreadOutput
  #     .then (thread) =>
  #       console.log thread
  #       thread = _.defaults {
  #         groupId: '68acb51a-3e5a-466a-9e31-c93aacd5919e'
  #       }, thread
  #       delete thread.time
  #       delete thread.get
  #       delete thread.values
  #       delete thread.keys
  #       delete thread.forEach
  #       console.log thread
  #       @deleteByThread thread
  #       .then =>
  #         @upsert thread
  #   .then ->
  #     console.log 'done'

  # didn't work w/ threads, but keeping code for now
  # migrateComments: (threadIds) ->
  #   ThreadComment = require './thread_comment'
  #   threadIds = [
  #     # {
  #     #   oldId: 'b3d49e6f-3193-417e-a584-beb082196a2c'
  #     #   newId: '7a39b079-e6ce-11e7-9642-4b5962cd09d3'
  #     # }
  #     {
  #       oldId: '90c06cb0-86ce-4ed6-9257-f36633db59c2'
  #       newId: 'fcb35890-f40e-11e7-9af5-920aa1303bef'
  #     }
  #   ]
  #   Promise.map threadIds, ({oldId, newId}) ->
  #     ThreadComment.getAllByThreadId oldId
  #     .then (comments) ->
  #       console.log comments.length
  #       comments
  #     .then (threadComments) ->
  #       Promise.map threadComments, (threadComment, i) ->
  #         console.log 'yes'
  #         newComment = {
  #           id: threadComment.id
  #           threadId: newId
  #           parentType: threadComment.parentType
  #           parentId: if "#{threadComment.parentId}" is "#{oldId}" then newId else threadComment.parentId
  #           creatorId: threadComment.creatorId
  #           body: threadComment.body
  #           timeBucket: threadComment.timeBucket
  #           timeUuid: cknex.getTimeUuid threadComment.timeUuid.getDate()
  #         }
  #         Promise.all [
  #           ThreadComment.upsert newComment
  #           ThreadComment.voteByThreadComment newComment, {
  #             upvotes: threadComment.upvotes or 0
  #             downvotes: threadComment.downvotes or 0
  #           }
  #         ]
  #         .then ->
  #           console.log 'd1', i
  #       , {concurrency: 10}
  #   .then ->
  #     console.log 'done'


  # migrateAll: (order) =>
  #   console.log 'migrate'
  #   r = require '../services/rethinkdb'
  #   Group = require './group'
  #   start = Date.now()
  #   gcache = {}
  #   CacheService.get 'migrate_threads_min_id5'
  #   .then (minId) =>
  #     minId ?= '0'
  #     # console.log 'migrate', minId
  #     r.table 'threads'
  #     .between minId, 'zzzz'
  #     .orderBy {index: r.asc('id')}
  #     .limit 2000
  #     .then (threads) =>
  #       console.log 'got', threads?.length
  #       Promise.map threads, (thread) =>
  #         # console.log thread.language
  #         (if gcache[config.DEFAULT_GAME_KEY + ':' + thread.language]
  #           Promise.resolve gcache[config.DEFAULT_GAME_KEY + ':' + thread.language]
  #         else
  #           Group.getByKeyAndLanguage config.DEFAULT_GAME_KEY, thread.language or 'en'
  #           .then (group) ->
  #             gcache[config.DEFAULT_GAME_KEY + ':' + thread.language] = group
  #             group
  #         )
  #         .then (group) =>
  #           newId = cknex.getTimeUuid thread.addTime
  #           if thread.id in [
  #             'b3d49e6f-3193-417e-a584-beb082196a2c'
  #             '90c06cb0-86ce-4ed6-9257-f36633db59c2'
  #           ]
  #             console.log 'NEW ID', thread.id, newId
  #           newThread =
  #             id: newId
  #             timeBucket: 'MONTH-' + moment(thread.addTime).format 'YYYY-MM'
  #             creatorId: thread.creatorId
  #             groupId: group.id
  #             category: thread.category or 'general'
  #             data:
  #               title: thread.title
  #               body: thread.body
  #               type: thread.type
  #               attachments: thread.attachments
  #               lastUpdateTime: thread.lastUpdateTime
  #               extras: thread.data
  #           increment = {
  #             upvotes: thread.upvotes or 0
  #             downvotes: thread.downvotes or 0
  #           }
  #           # console.log newThread.groupId
  #           # console.log newThread, increment
  #           Promise.all [
  #             @upsert newThread
  #             @incrementById newThread.id, increment
  #           ]
  #       .catch (err) ->
  #         console.log err
  #       .then ->
  #         console.log 'migrate time', Date.now() - start, minId, _.last(threads).id
  #         CacheService.set 'migrate_threads_min_id5', _.last(threads).id

  # deleteOldThreadRecent: =>
  #   @getAllNewish()
  #   .then (results) ->
  #     Promise.map results, ({id}, i) ->
  #       # console.log 'deleteOldThreadRecent got', id
  #       # @getById id
  #       # .then (thread) ->
  #       time = id.getDate()
  #       hoursOld = (Date.now() - time.getTime()) / (3600 * 1000)
  #       # console.log 'deleteOldThreadRecent hoursOld', hoursOld, i, id
  #       if hoursOld > 36
  #         cknex().delete()
  #         .from 'threads_recent'
  #         .where 'partition', '=', 1
  #         .andWhere 'id', '=', id
  #         .run()
  #         .then ->
  #           console.log 'deleteOldThreadRecent deleted', hoursOld, i
  #     , {concurrency: 30}
  #     .then ->
  #       console.log 'done'


  sanitize: _.curry (requesterId, thread) ->
    _.pick thread, [
      'id'
      'creatorId'
      'creator'
      'data'
      'groupId'
      'playerDeck'
      'comments'
      'commentCount'
      'myVote'
      'score'
      'upvotes'
      'downvotes'
      'time'
      'embedded'
    ]

module.exports = new ThreadModel()
