_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
cknex = require '../services/cknex'
TimeService = require '../services/time'
CacheService = require '../services/cache'
GroupUser = require './group_user'

ONE_DAY_SECONDS = 3600 * 24
THREE_HOURS_SECONDS = 3600 * 3

defaultGroupUserXpTransaction = (groupUserXpTransaction) ->
  unless groupUserXpTransaction?
    return null

  _.defaults groupUserXpTransaction, {
    scaledTime: TimeService.getScaledTimeByTimeScale 'day'
  }

defaultGroupUserXpTransactionOutput = (groupUserXpTransaction) ->
  unless groupUserXpTransaction?
    return null

  groupUserXpTransaction.count ?= 0
  groupUserXpTransaction.count = parseInt groupUserXpTransaction.count
  groupUserXpTransaction


tables = [
  {
    name: 'group_user_xp_actions'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      scaledTime: 'text'
      actionKey: 'text'
      xpAmount: 'int' # if we use counter, we can't use ttl
      count: 'int'
    primaryKey:
      partitionKey: ['userId', 'groupId', 'scaledTime']
      clusteringColumns: ['actionKey']
  }
]

class GroupUserXpTransactionModel
  SCYLLA_TABLES: tables
  ACTIONS:
    dailyVisit:
      xp: 5
      maxCount: 1
      ttl: ONE_DAY_SECONDS
    dailyChatMessage:
      xp: 5
      maxCount: 1
      ttl: ONE_DAY_SECONDS
    dailyVideoView:
      xp: 5
      maxCount: 1
      ttl: ONE_DAY_SECONDS
    rewardedVideos:
      xp: 5
      maxCount: 3
      ttl: THREE_HOURS_SECONDS

  upsert: (groupUserXpTransaction, {ttl} = {}) ->
    groupUserXpTransaction = defaultGroupUserXpTransaction(
      groupUserXpTransaction
    )

    q = cknex().update 'group_user_xp_actions'
    .set _.omit groupUserXpTransaction, [
      'userId', 'groupId', 'scaledTime', 'actionKey'
    ]
    .where 'userId', '=', groupUserXpTransaction.userId
    .andWhere 'groupId', '=', groupUserXpTransaction.groupId
    .andWhere 'scaledTime', '=', groupUserXpTransaction.scaledTime
    .andWhere 'actionKey', '=', groupUserXpTransaction.actionKey

    if ttl
      q.usingTTL ttl

    q.run()
    .then ->
      groupUserXpTransaction

  getAllByUserIdAndGroupIdAndScaledTime: (userId, groupId, scaledTime) ->
    cknex().select '*'
    .from 'group_user_xp_actions'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .andWhere 'scaledTime', '=', scaledTime
    .run()
    .map defaultGroupUserXpTransactionOutput

  completeActionByGroupIdAndUserId: (groupId, userId, actionKey) =>
    prefix = CacheService.PREFIXES.GROUP_USER_XP_COMPLETE_TRANSACTION
    key = "#{prefix}:#{groupId}:#{userId}:#{actionKey}"
    CacheService.lock key, =>
      scaledTime = TimeService.getScaledTimeByTimeScale 'day'
      @getAllByUserIdAndGroupIdAndScaledTime userId, groupId, scaledTime
      .then (xpTransactions) =>
        action = @ACTIONS[actionKey]
        unless action
          throw new Error 'action not found'

        existingTransaction = _.find xpTransactions, {actionKey}
        if existingTransaction?.count >= action.maxCount
          throw new Error 'already claimed'

        ttl = if existingTransaction then null else action.ttl
        xp = action.xp
        count = (existingTransaction?.count or 0) + 1
        Promise.all [
          GroupUser.incrementXpByGroupIdAndUserId groupId, userId, xp
          @upsert(
            {userId, groupId, scaledTime, actionKey, count}, {ttl}
          )
        ]
        .then -> xp
    , {expireSeconds: 10, unlockWhenCompleted: true}

module.exports = new GroupUserXpTransactionModel()
