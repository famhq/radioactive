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

  _.defaults _.pickBy(chatMessage), {
    id: uuid.v4()
    clientId: uuid.v4()
    groupId: config.EMPTY_UUID
    timeBucket: TimeService.getScaledTimeByTimeScale 'week'
    timeUuid: cknex.getTimeUuid()
    body: ''
  }

defaultChatMessageOutput = (chatMessage) ->
  unless chatMessage?
    return null

  if chatMessage.groupId is config.EMPTY_UUID
    chatMessage.groupId = null

  chatMessage

tables = [
  {
    name: 'chat_messages_by_conversationId'
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

  upsert: (chatMessage) =>
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
    .then =>
      @streamCreate chatMessage
      chatMessage

  getAllByConversationId: (conversationId, options = {}) =>
    {limit, isStreamed, emit, socket, route, postFn,
      minTime, maxTime, reverse} = options

    timeBucket = TimeService.getScaledTimeByTimeScale 'week', moment(minTime)

    get = (timeBucket) ->
      cknex().select '*'
      .from 'chat_messages_by_conversationId'
      .where 'conversationId', '=', conversationId
      .andWhere 'timeBucket', '=', timeBucket
      .limit limit
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

    if isStreamed
      @stream {
        emit
        socket
        route
        initial
        postFn
        channelBy: 'conversationId'
        channelById: conversationId
      }
    else
      initial

  getAllByGroupIdAndUserId: (groupId, userId) ->
    cknex().select '*'
    .from 'chat_messages_by_groupId_and_userId'
    .where 'groupId', '=', groupId
    .andWhere 'userId', '=', userId
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

  updateById: (id, diff) =>
    @getById id
    .then (chatMessage) =>
      @upsert chatMessage
    .tap =>
      @streamUpdateById id, diff

  deleteAllByGroupIdAndUserId: (groupId, userId) =>
    @getAllByGroupIdAndUserId groupId, userId
    .map @deleteByChatMessage

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
