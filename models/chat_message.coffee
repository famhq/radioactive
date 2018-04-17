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
  {
    name: 'chat_messages_slow_mode_log'
    keyspace: 'starfire'
    fields:
      conversationId: 'uuid'
      userId: 'uuid'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['conversationId', 'userId']
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

  getLastTimeByUserIdAndConversationId: (userId, conversationId) ->
    cknex().select '*'
    .from 'chat_messages_slow_mode_log'
    .where 'conversationId', '=', conversationId
    .andWhere 'userId', '=', userId
    .run {isSingle: true}
    .then (response) ->
      response?.time

  upsertSlowModeLog: ({userId, conversationId}) ->
    cknex().update 'chat_messages_slow_mode_log'
    .set {time: new Date()}
    .where 'conversationId', '=', conversationId
    .andWhere 'userId', '=', userId
    .usingTTL 3600 * 24 # 1 day
    .run()

  getAllByConversationId: (conversationId, options = {}) =>
    {limit, isStreamed, emit, socket, route, initialPostFn, postFn,
      minTimeUuid, maxTimeUuid, reverse} = options

    minTime = if minTimeUuid \
              then cknex.getTimeUuidFromString(minTimeUuid).getDate()
              else undefined

    maxTime = if maxTimeUuid \
              then cknex.getTimeUuidFromString(maxTimeUuid).getDate()
              else undefined

    timeBucket = TimeService.getScaledTimeByTimeScale(
      'week', moment(minTime or maxTime)
    )

    console.log 'go', minTimeUuid

    get = (timeBucket) ->
      q = cknex().select '*'
      .from 'chat_messages_by_conversationId'
      .where 'conversationId', '=', conversationId
      .andWhere 'timeBucket', '=', timeBucket

      if minTimeUuid
        q.andWhere 'timeUuid', '>=', minTimeUuid

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
      .map (initialPostFn or _.identity)

  unsubscribeByConversationId: (conversationId, {socket}) =>
    @unsubscribe {
      socket: socket
      channelBy: 'conversationId'
      channelById: conversationId
    }

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

module.exports = new ChatMessageModel()
