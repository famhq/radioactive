_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
Group = require './group'
Event = require './event'

ONE_DAY_S = 3600 * 24

defaultConversation = (conversation) ->
  unless conversation?
    return null

  conversation.id ?= cknex.getTimeUuid conversation.lastUpdateTime
  conversation.data = JSON.stringify conversation.data

  conversation

defaultConversationOutput = (conversation) ->
  unless conversation?
    return null

  conversation.data = try
    JSON.parse conversation.data
  catch err
    {}

  conversation.userIds = _.map conversation.userIds, (userId) -> "#{userId}"
  if conversation.userId
    conversation.userId = "#{conversation.userId}"
  if conversation.groupId
    conversation.groupId = "#{conversation.groupId}"

  conversation

tables = [
  {
    name: 'conversations_by_userId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid' # not unique - 1 row per userId
      userId: 'uuid'
      userIds: {type: 'set', subType: 'uuid'}
      groupId: 'uuid'
      type: 'text'
      data: 'text' # json: name, description, slowMode, slowModeCooldown
      isRead: 'boolean'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'conversations_by_groupId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid' # not unique - 1 row per userId
      userId: 'uuid'
      userIds: {type: 'set', subType: 'uuid'}
      groupId: 'uuid'
      type: 'text'
      data: 'text' # json: name, description, slowMode, slowModeCooldown
      isRead: 'boolean'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'conversations_by_id'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      userIds: {type: 'set', subType: 'uuid'}
      groupId: 'uuid'
      type: 'text'
      data: 'text' # json: name, description, slowMode, slowModeCooldown
      isRead: 'boolean'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
]

class ConversationModel
  SCYLLA_TABLES: tables

  upsert: (conversation, {userId} = {}) ->
    conversation = defaultConversation conversation

    Promise.all _.filter _.flatten [
      _.map conversation.userIds, (conversationUserId) ->
        conversation.isRead = conversationUserId is userId
        cknex().update 'conversations_by_userId'
        .set _.omit conversation, ['userId', 'id']
        .where 'userId', '=', conversationUserId
        .andWhere 'id', '=', conversation.id
        .run()

      if conversation.groupId
        cknex().update 'conversations_by_groupId'
        .set _.omit conversation, ['groupId', 'id']
        .where 'groupId', '=', conversation.groupId
        .andWhere 'id', '=', conversation.id
        .run()

      cknex().update 'conversations_by_id'
      .set _.omit conversation, ['id']
      .where 'id', '=', conversation.id
      .run()
    ]
    .tap ->
      prefix = CacheService.PREFIXES.CONVERSATION_ID
      key = "#{prefix}:#{conversation.id}"
      CacheService.deleteByKey key
    .then ->
      conversation

  getById: (id, {preferCache} = {}) ->
    preferCache ?= true
    get = ->
      cknex().select '*'
      .from 'conversations_by_id'
      .where 'id', '=', id
      .run {isSingle: true}
      .then defaultConversationOutput
      .catch (err) ->
        console.log 'covnersation get err', id
        throw err

    if preferCache
      prefix = CacheService.PREFIXES.CONVERSATION_ID
      key = "#{prefix}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_S}
    else
      get()

  getByGroupIdAndName: (groupId, name) =>
    @getAllByGroupId groupId
    .then (conversations) ->
      _.find conversations, {name}
    .then defaultConversationOutput

  getAllByUserId: (userId, {limit} = {}) ->
    limit ?= 10

    # TODO: use a redis leaderboard for sorting by last update?
    cknex().select '*'
    .from 'conversations_by_userId'
    .where 'userId', '=', userId
    .limit 1000
    .run()
    .then (conversations) ->
      conversations = _.filter conversations, (conversation) ->
        conversation.type is 'pm' and conversation.lastUpdateTime
      conversations = _.orderBy conversations, 'lastUpdateTime', 'desc'
      conversations = _.take conversations, limit
    .map defaultConversationOutput

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'conversations_by_groupId'
    .where 'groupId', '=', groupId
    .run()
    .map defaultConversationOutput

  getByUserIds: (checkUserIds, {limit} = {}) =>
    @getAllByUserId checkUserIds[0], {limit: 2500}
    .then (conversations) ->
      _.find conversations, ({type, userIds}) ->
        type is 'pm' and _.every checkUserIds, (userId) ->
          userIds.indexOf(userId) isnt -1
    .then defaultConversation

  hasPermission: (conversation, userId) ->
    if conversation.groupId
      Group.hasPermissionByIdAndUserId conversation.groupId, userId
    else if conversation.eventId
      Event.getById conversation.eventId
      .then (event) ->
        event and event.userIds.indexOf(userId) isnt -1
    else
      Promise.resolve userId and conversation.userIds.indexOf(userId) isnt -1

  markRead: ({id}, userId) ->
    cknex().update 'conversations_by_userId'
    .set {isRead: true}
    .where 'userId', '=', userId
    .andWhere 'id', '=', id
    .run()

  sanitize: _.curry (requesterId, conversation) ->
    _.pick conversation, [
      'id'
      'userIds'
      'data'
      'users'
      'groupId'
      'lastUpdateTime'
      'lastMessage'
      'isRead'
      'embedded'
    ]

  # migrateAll: =>
  #   CacheService = require '../services/cache'
  #   r = require '../services/rethinkdb'
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_conversations_min_id8'
  #     .then (minId) =>
  #       minId ?= '0000'
  #       r.table 'conversations'
  #       .between minId, 'zzzz'
  #       .orderBy {index: r.asc('id')}
  #       .limit 500
  #       .then (conversations) =>
  #         Promise.map conversations, (conversation) =>
  #           if conversation.type is 'pm' and not conversation.lastUpdateTime
  #             return Promise.resolve null
  #           conversation.data ?= {}
  #           conversation.data.name = conversation.name
  #           conversation.data.description = conversation.description
  #           conversation.data.legacyId = conversation.id
  #           conversation = _.pick conversation, ['userIds', 'groupId', 'type', 'data', 'isRead', 'lastUpdateTime']
  #           conversation.isRead = true
  #           @upsert conversation
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate time', Date.now() - start, minId, _.last(conversations)?.id
  #           CacheService.set 'migrate_conversations_min_id8', _.last(conversations)?.id
  #           .then ->
  #             _.last(conversations)?.id
  #
  #     CacheService.get 'migrate_conversations_max_id8'
  #     .then (maxId) =>
  #       maxId ?= 'zzzz'
  #       r.table 'conversations'
  #       .between '0000', maxId
  #       .orderBy {index: r.desc('id')}
  #       .limit 500
  #       .then (conversations) =>
  #         Promise.map conversations, (conversation) =>
  #           if conversation.type is 'pm' and not conversation.lastUpdateTime
  #             return Promise.resolve null
  #           conversation.data ?= {}
  #           conversation.data.name = conversation.name
  #           conversation.data.description = conversation.description
  #           conversation.data.legacyId = conversation.id
  #           conversation = _.pick conversation, ['userIds', 'groupId', 'type', 'data', 'isRead', 'lastUpdateTime']
  #           conversation.isRead = true
  #           @upsert conversation
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate time desc', Date.now() - start, maxId, _.last(conversations)?.id
  #           CacheService.set 'migrate_conversations_max_id8', _.last(conversations)?.id
  #           .then ->
  #             _.last(conversations)?.id
  #       ]
  #
  #   .then ([l1, l2]) =>
  #     if l1 and l2 and l1 < l2
  #       @migrateAll()

module.exports = new ConversationModel()
