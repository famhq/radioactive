_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'

# topics are NOT secure. anyone can subscribe. for secure messaging, always
# use the devicePushTopic. for private channels, use devicePushTopic

# TODO: figure out how to handle notifications to user.
# push_tokens should have a appKey on them too, so we select first for group app
# then fallback to main app

###
    // topics:
    // store subscriptions in database
      // <userId>, <groupId, appKey, sourceType, sourceId>
      // topic structure: groupId:appKey:sourceType:sourceId
      // eg: 12345:conversation:54321

    // when subscribing to group topic, unsubscribe from the main app one
    // only subscribe to group topics in group app
###

tables = [
  {
    name: 'push_topics_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid' # config.EMPTY_UUID for all
      appKey: 'text'
      sourceType: 'text' # conversation, video, thread, etc...
      sourceId: 'text' # id or 'all'
      token: 'text'
      deviceId: 'text'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: [
        'token', 'groupId', 'appKey', 'sourceType', 'sourceId'
      ]
  }
]

defaultPushTopic = (pushTopic) ->
  unless pushTopic?
    return null

  _.defaults pushTopic, {
    sourceType: 'all'
    sourceId: 'all'
    appKey: 'openfam'
    lastUpdateTime: new Date()
  }

defaultPushTopicOutput = (pushTopic) ->
  unless pushTopic?
    return null

  pushTopic.groupId = "#{pushTopic.groupId}"
  pushTopic

class PushTopic
  SCYLLA_TABLES: tables

  upsert: (pushTopic) ->
    # TODO: more elegant solution to stripping what lodash adds w/ _.defaults
    delete pushTopic.get
    delete pushTopic.values
    delete pushTopic.keys
    delete pushTopic.forEach

    pushTopic = defaultPushTopic pushTopic

    Promise.all [
      cknex().update 'push_topics_by_userId'
      .set _.omit pushTopic, [
        'userId', 'token', 'groupId', 'appKey', 'sourceType', 'sourceId'
      ]
      .where 'userId', '=', pushTopic.userId
      .andWhere 'token', '=', pushTopic.token
      .andWhere 'groupId', '=', pushTopic.groupId
      .andWhere 'appKey', '=', pushTopic.appKey
      .andWhere 'sourceType', '=', pushTopic.sourceType
      .andWhere 'sourceId', '=', pushTopic.sourceId
      .run()
    ]
    .then ->
      pushTopic

  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'push_topics_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultPushTopicOutput

  deleteByPushTopic: (pushTopic) ->
    cknex().delete()
    .from 'push_topics_by_userId'
    .where 'userId', '=', pushTopic.userId
    .andWhere 'token', '=', pushTopic.token
    .andWhere 'groupId', '=', pushTopic.groupId
    .andWhere 'appKey', '=', pushTopic.appKey
    .andWhere 'sourceType', '=', pushTopic.sourceType
    .andWhere 'sourceId', '=', pushTopic.sourceId
    .run()

  deleteByPushToken: (pushToken) ->
    cknex().delete()
    .from 'push_topics_by_userId'
    .where 'userId', '=', pushToken.userId
    .andWhere 'token', '=', pushToken.token
    .run()

  deleteByUserIdAndToken: (userId, token) ->
    cknex().delete()
    .from 'push_topics_by_userId'
    .where 'userId', '=', pushTopic.userId
    .andWhere 'token', '=', pushTopic.token
    .run()

module.exports = new PushTopic()
