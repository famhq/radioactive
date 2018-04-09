_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
cknex = require '../services/cknex'
TimeService = require '../services/time'
CacheService = require '../services/cache'
GroupUser = require './group_user'
UserItem = require './user_item'

ONE_DAY_SECONDS = 3600 * 24
THREE_HOURS_SECONDS = 3600 * 3

defaultEarnTransaction = (earnTransaction) ->
  unless earnTransaction?
    return null

  earnTransaction

defaultEarnTransactionOutput = (earnTransaction) ->
  unless earnTransaction?
    return null

  earnTransaction.count ?= 0
  earnTransaction.count = parseInt earnTransaction.count
  earnTransaction

defaultEarnAction = (earnAction) ->
  unless earnAction?
    return null

  earnAction.data = JSON.stringify earnAction.data

  earnAction

defaultEarnActionOutput = (earnAction) ->
  unless earnAction?
    return null

  if earnAction.data
    earnAction.data = try
      JSON.parse earnAction.data
    catch err
      {}

  earnAction

tables = [
  {
    name: 'earn_actions'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      name: 'text'
      action: 'text'
      ttl: 'int'
      data: 'text'
      maxCount: 'int'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['action']
  }
  {
    name: 'earn_transactions'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      action: 'text'
      count: 'int'
    primaryKey:
      partitionKey: ['userId', 'groupId']
      clusteringColumns: ['action']
  }
]

class EarnActionModel
  SCYLLA_TABLES: tables

  batchUpsert: (earnActions) =>
    Promise.map earnActions, (earnAction) =>
      @upsert earnAction

  upsert: (earnAction) ->
    earnAction = _.cloneDeep earnAction
    earnAction = defaultEarnAction earnAction
    cknex().update 'earn_actions'
    .set _.omit earnAction, ['groupId', 'action']
    .where 'groupId', '=', earnAction.groupId
    .andWhere 'action', '=', earnAction.action
    .run()

  upsertTransaction: (earnTransaction, {ttl} = {}) ->
    earnTransaction = defaultEarnTransaction(
      earnTransaction
    )

    q = cknex().update 'earn_transactions'
    .set _.omit earnTransaction, [
      'userId', 'groupId', 'action'
    ]
    .where 'userId', '=', earnTransaction.userId
    .andWhere 'groupId', '=', earnTransaction.groupId
    .andWhere 'action', '=', earnTransaction.action

    if ttl
      q.usingTTL ttl

    q.run()
    .then ->
      earnTransaction

  getAllTransactionsByUserIdAndGroupId: (userId, groupId) ->
    cknex().select '*'
    .from 'earn_transactions'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .run()
    .map defaultEarnTransactionOutput

  getAllByGroupId: (groupId) =>
    cknex().select '*'
    .from 'earn_actions'
    .where 'groupId', '=', groupId
    .run()
    .map defaultEarnActionOutput
    .then (actions) =>
      if _.isEmpty actions
        @getStandardActionsByGroupId groupId
      else
        actions

  getByGroupIdAndAction: (groupId, action) =>
    cknex().select '*'
    .from 'earn_actions'
    .where 'groupId', '=', groupId
    .andWhere 'action', '=', action
    .run {isSingle: true}
    .then defaultEarnActionOutput
    .then (existingAction) =>
      existingAction or _.find(@getStandardActionsByGroupId(groupId), {action})

  completeActionByGroupIdAndUserId: (groupId, userId, action) =>
    prefix = CacheService.PREFIXES.EARN_COMPLETE_TRANSACTION
    key = "#{prefix}:#{userId}:#{action}"
    CacheService.lock key, =>
      Promise.all [
        @getByGroupIdAndAction groupId, action
        @getAllTransactionsByUserIdAndGroupId userId, groupId
      ]
      .then ([action, transactions]) =>
        unless action
          throw new Error 'action not found'

        existingTransaction = _.find transactions, {action: action.action}
        if existingTransaction?.count >= action.maxCount
          throw new Error 'already claimed'

        ttl = if existingTransaction then null else action.ttl
        count = (existingTransaction?.count or 0) + 1
        Promise.all [
          Promise.map action.data.rewards, (reward) ->
            if reward.currencyType is 'xp'
              GroupUser.incrementXpByGroupIdAndUserId(
                groupId, userId, reward.currencyAmount
              )
            else
              UserItem.incrementByItemKeyAndUserId(
                reward.currencyItemKey, userId, reward.currencyAmount
              )

          @upsertTransaction(
            {userId, groupId, action: action.action, count}, {ttl}
          )
        ]
        .then ->
          action.data.rewards
    , {expireSeconds: 10, unlockWhenCompleted: true}

  # for if custom ones aren't set for group
  getStandardActionsByGroupId: (groupId) ->
    [
      {
        key: "#{groupId}_daily_visit"
        name: 'Daily visit'
        groupId: groupId
        action: 'visit'
        data:
          nameKey: 'earnXp.dailyVisit'
          rewards: [
            {currencyAmount: 5, currencyType: 'xp'}
          ]
          button:
            textKey: 'earnXp.claim'
        maxCount: 1
        ttl: ONE_DAY_SECONDS
      }
      {
        key: "#{groupId}_daily_chat_message"
        name: 'Daily chat message'
        groupId: groupId
        action: 'chatMessage'
        data:
          nameKey: 'earnXp.dailyChatMessage'
          rewards: [
            {currencyAmount: 5, currencyType: 'xp'}
          ]
          button:
            textKey: 'earnXp.dailyChatMessageButton'
            route:
              key: 'groupChat'
              replacements: {groupId: 'groupId'}
        maxCount: 1
        ttl: ONE_DAY_SECONDS
      }
      {
        key: "#{groupId}_daily_forum_comment"
        name: 'Daily forum comment'
        groupId: groupId
        action: 'forumComment'
        data:
          nameKey: 'earnXp.dailyForumComment'
          rewards: [
            {currencyAmount: 5, currencyType: 'xp'}
          ]
          button:
            textKey: 'earnXp.dailyVideoViewButton'
            route:
              key: 'groupVideos'
              replacements: {groupId: 'groupId'}
        maxCount: 1
        ttl: ONE_DAY_SECONDS
      }
      {
        key: "#{groupId}_rewarded_videos"
        name: 'Watch ad'
        groupId: groupId
        action: 'watchAd'
        data:
          nameKey: 'earnXp.watchAd'
          rewards: [
            {currencyAmount: 1, currencyType: 'xp'}
          ]
          button:
            textKey: 'earnXp.watchAd'
        maxCount: 3
        ttl: THREE_HOURS_SECONDS
      }
    ]

module.exports = new EarnActionModel()
