_ = require 'lodash'
uuid = require 'uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

UNREAD_TTL = 3600 * 24 * 365 # 1y
READ_TTL = 3600 * 24 * 7 # 1w

defaultGroupNotification = (groupNotification) ->
  unless groupNotification?
    return null

  if groupNotification.data
    groupNotification.data = JSON.stringify groupNotification.data

  Object.assign {id: cknex.getTimeUuid(), isRead: false}, groupNotification

defaultGroupNotificationOutput = (groupNotification) ->
  unless groupNotification?
    return null

  if groupNotification.data
    groupNotification.data = try
      JSON.parse groupNotification.data
    catch err
      {}

  groupNotification

###
notification when mentioned (@everyone seems pretty expensive...) FIXME: solution
  - could have a separate table for group_notifications_by_roleId and merge
    results. create new by_userId when the role one is read, and prefer user ones when merging

notification when self mentioned in conversation: easy

trade notification i guess by groupId for now
###

tables = [
  {
    name: 'group_notifications_by_userId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      groupId: 'uuid'
      uniqueId: 'text' # used so there's not a bunch of dupe messages
      fromId: 'uuid'
      title: 'text'
      text: 'text'
      isRead: 'boolean'
      data: 'text' # JSON conversationId
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId', 'id']
    withClusteringOrderBy: [['groupId', 'desc'], ['id', 'desc']]
  }
  {
    name: 'group_notifications_by_userId_and_uniqueId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      groupId: 'uuid'
      uniqueId: 'text' # used so there's not a bunch of dupe messages
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['uniqueId']
  }
  {
    name: 'group_notifications_by_roleId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      roleId: 'uuid'
      groupId: 'uuid'
      uniqueId: 'text' # used so there's not a bunch of dupe messages
      fromId: 'uuid'
      title: 'text'
      text: 'text'
      isRead: 'boolean'
      data: 'text' # JSON conversationId
    primaryKey:
      partitionKey: ['roleId']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
]

class GroupNotificationModel
  SCYLLA_TABLES: tables

  upsert: (groupNotification) =>
    groupNotification = defaultGroupNotification groupNotification

    (if groupNotification.uniqueId
      @getByUserIdAndUniqueId(
        groupNotification.userId, groupNotification.uniqueId
      )
      .tap (existingNotification) =>
        if existingNotification
          @deleteByGroupNotification existingNotification
      .then ->
        groupNotification
    else
      groupNotification.uniqueId = uuid.v4()
      Promise.resolve groupNotification
    )
    .then (groupNotification) ->
      # FIXME: i think lodash or cassanknex is adding these, but can't find where...
      setUser = _.omit groupNotification, ['userId', 'groupId', 'id']
      setRole = _.omit groupNotification, ['roleId', 'id']
      delete setUser.get
      delete setUser.values
      delete setUser.keys
      delete setUser.forEach
      delete setRole.get
      delete setRole.values
      delete setRole.keys
      delete setRole.forEach

      if groupNotification.isRead
        ttl = READ_TTL
      else
        ttl = UNREAD_TTL
      Promise.all _.filter _.flatten [
        if groupNotification.userId
          [
            cknex().update 'group_notifications_by_userId'
            .set setUser
            .where 'userId', '=', groupNotification.userId
            .andWhere 'groupId', '=', groupNotification.groupId
            .andWhere 'id', '=', groupNotification.id
            .usingTTL ttl
            .run()

            cknex().update 'group_notifications_by_userId_and_uniqueId'
            .set _.pick groupNotification, ['id' ,'groupId']
            .where 'userId', '=', groupNotification.userId
            .andWhere 'uniqueId', '=', groupNotification.uniqueId
            .usingTTL ttl
            .run()
         ]

        if groupNotification.roleId
          cknex().update 'group_notifications_by_roleId'
          .set setRole
          .where 'roleId', '=', groupNotification.roleId
          .andWhere 'id', '=', groupNotification.id
          .usingTTL ttl
          .run()
      ]
      .then ->
        groupNotification

  getAllByUserId: (userId) ->
    cknex().select '*'
    .from 'group_notifications_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultGroupNotificationOutput

  getByUserIdAndUniqueId: (userId, uniqueId) ->
    cknex().select '*'
    .from 'group_notifications_by_userId_and_uniqueId'
    .where 'userId', '=', userId
    .andWhere 'uniqueId', '=', uniqueId
    .run {isSingle: true}
    .then defaultGroupNotificationOutput

  getAllByUserIdAndGroupId: (userId, groupId) ->
    cknex().select '*'
    .from 'group_notifications_by_userId'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .run()
    .map defaultGroupNotificationOutput

  getAllByRoleId: (roleId) ->
    cknex().select '*'
    .from 'group_notifications_by_roleId'
    .where 'roleId', '=', roleId
    .run()
    .map defaultGroupNotificationOutput

  deleteByGroupNotification: (groupNotification) ->
    Promise.all _.filter _.flatten [
      if groupNotification.userId
        [
          cknex().delete()
          .from 'group_notifications_by_userId'
          .where 'userId', '=', groupNotification.userId
          .andWhere 'groupId', '=', groupNotification.groupId
          .andWhere 'id', '=', groupNotification.id
          .run()

          cknex().delete()
          .from 'group_notifications_by_userId_and_uniqueId'
          .where 'userId', '=', groupNotification.userId
          .andWhere 'uniqueId', '=', groupNotification.uniqueId
          .run()
       ]

      if groupNotification.roleId
        cknex().delete()
        .from 'group_notifications_by_roleId'
        .where 'roleId', '=', groupNotification.roleId
        .andWhere 'id', '=', groupNotification.id
        .run()
    ]

module.exports = new GroupNotificationModel()
