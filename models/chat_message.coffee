_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'
uuid = require 'node-uuid'

StreamService = require '../services/stream'
TimeService = require '../services/time'
CacheService = require '../services/cache'
r = require '../services/rethinkdb'
cknex = require '../services/cknex'
Stream = require './stream'
config = require '../config'

defaultChatMessage = (chatMessage) ->
  unless chatMessage?
    return null

  chatMessage = _.defaults _.pickBy(chatMessage), {
    id: uuid.v4()
    clientId: uuid.v4()
    groupId: config.EMPTY_UUID
    timeBucket: TimeService.getScaledTimeByTimeScale 'week'
    timeUuid: cknex.getTimeUuid()
    lastUpdateTime: new Date()
    body: ''
  }
  if chatMessage.card
    chatMessage.card = try
      JSON.stringify chatMessage.card
    catch err
      ''
  chatMessage

defaultChatMessageOutput = (chatMessage) ->
  unless chatMessage?
    return null

  if chatMessage.groupId is config.EMPTY_UUID
    chatMessage.groupId = null

  if chatMessage.card
    chatMessage.card = try
      JSON.parse chatMessage.card
    catch err
      null

  chatMessage

tables = [
  {
    name: 'chat_messages_by_conversationId'
    keyspace: 'starfire'
    fields:
      # ideally we should change this to timeuuid and get rid of timeUuid col
      id: 'uuid'
      conversationId: 'uuid'
      clientId: 'uuid'
      userId: 'uuid'
      groupId: 'uuid'
      body: 'text'
      card: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['conversationId', 'timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
  # for showing all of a user's messages, and potentially deleting all
  {
    name: 'chat_messages_by_groupId_and_userId'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      conversationId: 'uuid'
      clientId: 'uuid'
      userId: 'uuid'
      groupId: 'uuid'
      body: 'text'
      card: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['groupId', 'userId', 'timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
  # for deleting by id
  {
    name: 'chat_messages_by_id'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      conversationId: 'uuid'
      clientId: 'uuid'
      userId: 'uuid'
      groupId: 'uuid'
      body: 'text'
      card: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['id']
  }
]

class ChatMessageModel extends Stream
  SCYLLA_TABLES: tables

  constructor: ->
    @streamChannelKey = 'chat_message'
    @streamChannelsBy = ['conversationId']

  default: defaultChatMessageOutput

  upsert: (chatMessage, {prepareFn, isUpdate} = {}) =>
    chatMessage = defaultChatMessage chatMessage

    Promise.all [
      cknex().update 'chat_messages_by_conversationId'
      .set _.omit chatMessage, [
        'conversationId', 'timeBucket', 'timeUuid'
      ]
      .where 'conversationId', '=', chatMessage.conversationId
      .andWhere 'timeBucket', '=', chatMessage.timeBucket
      .andWhere 'timeUuid', '=', chatMessage.timeUuid
      .run()

      cknex().update 'chat_messages_by_groupId_and_userId'
      .set _.omit chatMessage, [
        'groupId', 'userId', 'timeBucket', 'timeUuid'
      ]
      .where 'groupId', '=', chatMessage.groupId
      .andWhere 'userId', '=', chatMessage.userId
      .andWhere 'timeBucket', '=', chatMessage.timeBucket
      .andWhere 'timeUuid', '=', chatMessage.timeUuid
      .run()

      cknex().update 'chat_messages_by_id'
      .set _.omit chatMessage, [
        'id'
      ]
      .where 'id', '=', chatMessage.id
      .run()
    ]
    .then ->
      prepareFn?(chatMessage) or chatMessage
    .then (chatMessage) =>
      unless isUpdate
        @streamCreate chatMessage
      chatMessage

  getAllByConversationId: (conversationId, options = {}) =>
    {limit, isStreamed, emit, socket, route, initialPostFn, postFn,
      minTime, maxTimeUuid, reverse} = options

    maxTime = if maxTimeUuid \
              then cknex.getTimeUuidFromString(maxTimeUuid).getDate()
              else undefined

    timeBucket = TimeService.getScaledTimeByTimeScale(
      'week', moment(minTime or maxTime)
    )

    get = (timeBucket) ->
      q = cknex().select '*'
      .from 'chat_messages_by_conversationId'
      .where 'conversationId', '=', conversationId
      .andWhere 'timeBucket', '=', timeBucket

      if maxTimeUuid
        q.andWhere 'timeUuid', '<', maxTimeUuid

      q.limit limit
      .run()

    initial = get timeBucket
    .then (results) ->
      # if not enough results, check preivous time bucket. could do this more
      #  than once, but last 2 weeks of messages seems fine
      if limit and results.length < limit
        get TimeService.getPreviousTimeByTimeScale 'week', moment(minTime)
        .then (olderMessages) ->
          _.filter (results or []).concat olderMessages
      else
        results
    .then (results) ->
      if reverse
        results.reverse()
      results
      # FIXME FIXME: in early 2018 delete all messages from
      # timeBucket=WEEK-2017-46 (mid-nov) back. bunch of duplicates from bad
      # rethinkdb import
      _.uniqBy results, (chatMessage) -> "#{chatMessage.id}"

    if isStreamed
      @stream {
        emit
        socket
        route
        initial
        initialPostFn
        postFn
        channelBy: 'conversationId'
        channelById: conversationId
      }
    else
      initial

  getAllByGroupIdAndUserIdAndTimeBucket: (groupId, userId, timeBucket) ->
    cknex().select '*'
    .from 'chat_messages_by_groupId_and_userId'
    .where 'groupId', '=', groupId
    .andWhere 'userId', '=', userId
    .andWhere 'timeBucket', '=', timeBucket
    .run()
    .map defaultChatMessageOutput

  getById: (id) ->
    cknex().select '*'
    .from 'chat_messages_by_id'
    .where 'id', '=', id
    .run {isSingle: true}
    .then defaultChatMessageOutput

  deleteByChatMessage: (chatMessage) =>
    Promise.all [
      cknex().delete()
      .from 'chat_messages_by_conversationId'
      .where 'conversationId', '=', chatMessage.conversationId
      .andWhere 'timeBucket', '=', chatMessage.timeBucket
      .andWhere 'timeUuid', '=', chatMessage.timeUuid
      .run()

      cknex().delete()
      .from 'chat_messages_by_groupId_and_userId'
      .where 'groupId', '=', chatMessage.groupId
      .andWhere 'userId', '=', chatMessage.userId
      .andWhere 'timeBucket', '=', chatMessage.timeBucket
      .andWhere 'timeUuid', '=', chatMessage.timeUuid
      .run()

      cknex().delete()
      .from 'chat_messages_by_id'
      .where 'id', '=', chatMessage.id
      .run()
    ]
    .tap =>
      @streamDeleteById chatMessage.id, chatMessage

  getLastByConversationId: (conversationId) =>
    @getAllByConversationId conversationId, {limit: 1}
    .then (messages) ->
      messages?[0]
    .then defaultChatMessageOutput

  updateById: (id, diff, {prepareFn}) =>
    @getById id
    .then defaultChatMessageOutput
    .then (chatMessage) =>
      updatedMessage = _.defaults(diff, chatMessage)
      updatedMessage.lastUpdateTime = new Date()

      # hacky https://github.com/datastax/nodejs-driver/pull/243
      delete updatedMessage.get
      delete updatedMessage.values
      delete updatedMessage.keys
      delete updatedMessage.forEach

      @upsert updatedMessage, {isUpdate: true, prepareFn}
    .tap (chatMessage) =>
      @streamUpdateById id, chatMessage

  deleteAllByGroupIdAndUserId: (groupId, userId, {duration} = {}) =>
    duration ?= '7d' # TODO (doesn't actually do anything)

    del = (timeBucket) =>
      @getAllByGroupIdAndUserIdAndTimeBucket groupId, userId, timeBucket
      .map @deleteByChatMessage

    del TimeService.getScaledTimeByTimeScale 'week'
    del TimeService.getScaledTimeByTimeScale(
      'week'
      moment().subtract(1, 'week')
    )

  # migrateAll: (order) =>
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_chat_messages_min_id7'
  #     .then (minId) =>
  #       minId ?= '0'
  #       r.table 'chat_messages'
  #       .between minId, 'ZZZZ'
  #       .orderBy {index: r.asc('id')}
  #       .limit 500
  #       .then (chatMessages) =>
  #         Promise.map chatMessages, (chatMessage) =>
  #           chatMessage.timeUuid = cknex.getTimeUuid chatMessage.time
  #           chatMessage.timeBucket = TimeService.getScaledTimeByTimeScale 'week', moment(chatMessage.time)
  #           delete chatMessage.time
  #           @upsert chatMessage
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate time', Date.now() - start, minId, _.last(chatMessages).id
  #           CacheService.set 'migrate_chat_messages_min_id7', _.last(chatMessages).id
  #
  #     CacheService.get 'migrate_chat_messages_max_id7'
  #     .then (maxId) =>
  #       maxId ?= 'ZZZZ'
  #       r.table 'chat_messages'
  #       .between '0000', maxId
  #       .orderBy {index: r.desc('id')}
  #       .limit 500
  #       .then (chatMessages) =>
  #         Promise.map chatMessages, (chatMessage) =>
  #           chatMessage.timeUuid = cknex.getTimeUuid chatMessage.time
  #           chatMessage.timeBucket = TimeService.getScaledTimeByTimeScale 'week', moment(chatMessage.time)
  #           delete chatMessage.time
  #           @upsert chatMessage
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate time', Date.now() - start, maxId, _.last(chatMessages).id
  #           CacheService.set 'migrate_chat_messages_max_id7', _.last(chatMessages).id
  #       ]
  #
  #   .then =>
  #     @migrateAll()

module.exports = new ChatMessageModel()
