_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'

tables = [
  {
    name: 'push_tokens_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      token: 'text'
      sourceType: 'text'
      isActive: 'boolean'
      errorCount: 'int'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['token']
  }
  {
    name: 'push_tokens_by_token'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      token: 'text'
      sourceType: 'text'
      isActive: 'boolean'
      errorCount: 'int'
    primaryKey:
      partitionKey: ['token']
      clusteringColumns: ['userId']
  }
]

defaultToken = (token) ->
  unless token?
    return null

  _.defaults token, {
    sourceType: null
    token: null
    isActive: true
    userId: null
    errorCount: 0
  }

class PushToken
  SCYLLA_TABLES: tables

  upsert: (token) ->
    # TODO: more elegant solution to stripping what lodash adds w/ _.defaults
    delete token.get
    delete token.values
    delete token.keys
    delete token.forEach

    token = defaultToken token

    Promise.all [
      cknex().update 'push_tokens_by_userId'
      .set _.omit token, ['userId', 'token']
      .where 'userId', '=', token.userId
      .andWhere 'token', '=', token.token
      .run()

      cknex().update 'push_tokens_by_token'
      .set _.omit token, ['token', 'userId']
      .where 'token', '=', token.token
      .andWhere 'userId', '=', token.userId
      .run()
    ]
    .then ->
      token

  getByToken: (token) ->
    cknex().select '*'
    .from 'push_tokens_by_token'
    .where 'token', '=', token
    .run {isSingle: true}

  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'push_tokens_by_userId'
    .where 'userId', '=', userId
    .run()


  # migrateAll: =>
  #   CacheService = require '../services/cache'
  #   r = require '../services/rethinkdb'
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_push_tokens_min_id4'
  #     .then (minId) =>
  #       minId ?= '9999'
  #       r.table 'push_tokens'
  #       .between minId, 'zzzz'
  #       .orderBy {index: r.asc('id')}
  #       .limit 500
  #       .then (pushTokens) =>
  #         Promise.map pushTokens, (pushToken) =>
  #           pushToken = _.pick pushToken, ['userId', 'token', 'isActive', 'errorCount', 'sourceType']
  #           @upsert pushToken
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate token', Date.now() - start, minId, _.last(pushTokens)?.id
  #           CacheService.set 'migrate_push_tokens_min_id4', _.last(pushTokens)?.id
  #           .then ->
  #             _.last(pushTokens)?.id
  #
  #     CacheService.get 'migrate_push_tokens_max_id4'
  #     .then (maxId) =>
  #       maxId ?= 'zzzz'
  #       r.table 'push_tokens'
  #       .between '0000', maxId
  #       .orderBy {index: r.desc('id')}
  #       .limit 500
  #       .then (pushTokens) =>
  #         Promise.map pushTokens, (pushToken) =>
  #           pushToken = _.pick pushToken, ['userId', 'token', 'isActive', 'errorCount', 'sourceType']
  #           @upsert pushToken
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate token desc', Date.now() - start, maxId, _.last(pushTokens)?.id
  #           CacheService.set 'migrate_push_tokens_max_id4', _.last(pushTokens)?.id
  #           .then ->
  #             _.last(pushTokens)?.id
  #       ]
  #
  #   .then ([l1, l2]) =>
  #     if l1 and l2 and l1 < l2
  #       @migrateAll()

  sanitizePublic: (token) ->
    _.pick token, [
      'id'
      'userId'
      'token'
      'sourceType'
    ]


module.exports = new PushToken()
