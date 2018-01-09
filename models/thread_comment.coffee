_ = require 'lodash'
Promise = require 'bluebird'

uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
TimeService = require '../services/time'
User = require './user'

tables = [
  # sorting done in node

  # needs to have at least the keys that are partition keys from
  # other by_x tables (for updating all counters)
  {
    name: 'thread_comments_by_threadId'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      threadId: 'uuid'
      parentType: 'text'
      parentId: 'uuid'
      creatorId: 'uuid'
      body: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['threadId']
      clusteringColumns: [ 'parentType', 'parentId', 'timeUuid']
  }
  {
    name: 'thread_comments_counter_by_threadId'
    keyspace: 'starfire'
    fields:
      threadId: 'uuid'
      parentType: 'text'
      parentId: 'uuid'
      timeUuid: 'timeuuid'
      upvotes: 'counter'
      downvotes: 'counter'
    primaryKey:
      partitionKey: ['threadId']
      clusteringColumns: [ 'parentType', 'parentId', 'timeUuid']
  }


  {
    name: 'thread_comments_by_creatorId'
    keyspace: 'starfire'
    fields:
      # ideally we should change this to timeuuid and get rid of timeUuid col
      id: 'uuid'
      threadId: 'uuid'
      parentType: 'text'
      parentId: 'uuid'
      creatorId: 'uuid'
      body: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['creatorId', 'timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
  # do we even need this?
  {
    name: 'thread_comments_counter_by_creatorId'
    keyspace: 'starfire'
    fields:
      creatorId: 'uuid'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
      upvotes: 'counter'
      downvotes: 'counter'
    primaryKey:
      partitionKey: ['creatorId', 'timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
]

ONE_MONTH_MS = 3600 * 24 * 30 * 1000

defaultThreadComment = (threadComment) ->
  unless threadComment?
    return null

  _.defaults threadComment, {
    id: uuid.v4()
    timeUuid: cknex.getTimeUuid()
    timeBucket: TimeService.getScaledTimeByTimeScale 'month'
  }

class ThreadCommentModel
  SCYLLA_TABLES: tables

  upsert: (threadComment) ->
    threadComment = defaultThreadComment threadComment

    Promise.all [
      cknex().update 'thread_comments_by_creatorId'
      .set _.omit threadComment, [
        'creatorId', 'timeBucket', 'timeUuid'
      ]
      .where 'creatorId', '=', threadComment.creatorId
      .andWhere 'timeBucket', '=', threadComment.timeBucket
      .andWhere 'timeUuid', '=', threadComment.timeUuid
      .run()

      cknex().update 'thread_comments_by_threadId'
      .set _.omit threadComment, [
        'threadId', 'parentType', 'parentId', 'timeUuid'
      ]
      .where 'threadId', '=', threadComment.threadId
      .andWhere 'parentType', '=', threadComment.parentType
      .andWhere 'parentId', '=', threadComment.parentId
      .andWhere 'timeUuid', '=', threadComment.timeUuid
      .run()
    ]
    .then ->
      threadId = threadComment.threadId
      key = "#{CacheService.PREFIXES.THREAD_COMMENTS_THREAD_ID}:#{threadId}"
      CacheService.deleteByKey key
    .then ->
      threadComment

  voteByThreadComment: (threadComment, values) ->
    qByCreatorId = cknex().update 'thread_comments_counter_by_creatorId'
    _.forEach values, (value, key) ->
      qByCreatorId = qByCreatorId.increment key, value
    qByCreatorId = qByCreatorId.where 'creatorId', '=', threadComment.creatorId
    .andWhere 'timeBucket', '=', threadComment.timeBucket
    .andWhere 'timeUuid', '=', threadComment.timeUuid
    .run()

    qByThreadId = cknex().update 'thread_comments_counter_by_threadId'
    _.forEach values, (value, key) ->
      qByThreadId = qByThreadId.increment key, value
    qByThreadId = qByThreadId.where 'threadId', '=', threadComment.threadId
    .andWhere 'parentType', '=', threadComment.parentType
    .andWhere 'parentId', '=', threadComment.parentId
    .andWhere 'timeUuid', '=', threadComment.timeUuid
    .run()

    Promise.all [
      qByCreatorId
      qByThreadId
    ]

  getAllByThreadId: (threadId) ->
    # legacy. rm in mid feb 2018
    if threadId is 'b3d49e6f-3193-417e-a584-beb082196a2c' # cr-es
      threadId = '7a39b079-e6ce-11e7-9642-4b5962cd09d3'
    else if threadId is 'fcb35890-f40e-11e7-9af5-920aa1303bef' # bruno
      threadId = '90c06cb0-86ce-4ed6-9257-f36633db59c2'

    Promise.all [
      cknex().select '*'
      .from 'thread_comments_by_threadId'
      .where 'threadId', '=', threadId
      .run()

      cknex().select '*'
      .from 'thread_comments_counter_by_threadId'
      .where 'threadId', '=', threadId
      .run()
    ]
    .then ([allComments, voteCounts]) ->
      console.log 'got', allComments.length
      allComments = _.map allComments, (comment) ->
        voteCount = _.find voteCounts, {timeUuid: comment.timeUuid}
        voteCount ?= {upvotes: 0, downvotes: 0}
        _.merge comment, voteCount

  getCountByThreadId: (threadId) ->
    # legacy. rm in mid feb 2018
    if "#{threadId}" is 'b3d49e6f-3193-417e-a584-beb082196a2c' # cr-es
      threadId = '7a39b079-e6ce-11e7-9642-4b5962cd09d3'
    else if "#{threadId}" is 'fcb35890-f40e-11e7-9af5-920aa1303bef' # bruno
      threadId = '90c06cb0-86ce-4ed6-9257-f36633db59c2'

    cknex().select '*'
    .from 'thread_comments_by_threadId'
    .where 'threadId', '=', threadId
    .run()
    .then (threads) -> threads.length

  deleteByThreadComment: (threadComment) ->
    Promise.all [
      cknex().delete()
      .from 'thread_comments_by_threadId'
      .where 'threadId', '=', threadComment.threadId
      .andWhere 'parentType', '=', threadComment.parentType
      .andWhere 'parentId', '=', threadComment.parentId
      .andWhere 'timeUuid', '=', threadComment.timeUuid
      .run()

      cknex().delete()
      .from 'thread_comments_counter_by_threadId'
      .where 'threadId', '=', threadComment.threadId
      .andWhere 'parentType', '=', threadComment.parentType
      .andWhere 'parentId', '=', threadComment.parentId
      .andWhere 'timeUuid', '=', threadComment.timeUuid
      .run()

      cknex().delete()
      .from 'thread_comments_by_creatorId'
      .where 'creatorId', '=', threadComment.creatorId
      .andWhere 'timeBucket', '=', threadComment.timeBucket
      .run()

      cknex().delete()
      .from 'thread_comments_counter_by_creatorId'
      .where 'creatorId', '=', threadComment.creatorId
      .andWhere 'timeBucket', '=', threadComment.timeBucket
      .run()
    ]


  # would need another table to grab by id
  # getById: (id) ->
  #   cknex().select '*'
  #   .from 'thread_comments_by_threadId'
  #   .where 'id', '=', id
  #   .run {isSingle: true}

module.exports = new ThreadCommentModel()
