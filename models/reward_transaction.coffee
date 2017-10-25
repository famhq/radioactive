_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'

defaultRewardTransaction = (rewardTransaction) ->
  unless rewardTransaction?
    return null

  _.defaults rewardTransaction, {
    # 10-17-2017
    timeBucket: 'DAY-' + moment().format 'YYYY-MM-DD'
    timeUuid: cknex.getTimeUuid()
  }


tables = [
  {
    name: 'reward_transactions'
    keyspace: 'starfire'
    fields:
      network: 'text'
      txnId: 'text'
      userId: 'uuid'
      fireAmount: 'int'
      offerId: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['network', 'txnId']
      clusteringColumns: null
  }
  {
    name: 'reward_transactions_by_timeUuid'
    keyspace: 'starfire'
    fields:
      network: 'text'
      txnId: 'text'
      userId: 'uuid'
      fireAmount: 'int'
      offerId: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
  {
    name: 'reward_transactions_by_userId'
    keyspace: 'starfire'
    fields:
      network: 'text'
      txnId: 'text'
      userId: 'uuid'
      fireAmount: 'int'
      offerId: 'text'
      timeBucket: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['userId', 'timeBucket']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
]

class RewardTransactionModel
  SCYLLA_TABLES: tables

  upsert: (rewardTransaction) ->
    rewardTransaction = defaultRewardTransaction rewardTransaction

    Promise.all [
      cknex().update 'reward_transactions'
      .set _.omit rewardTransaction, ['network', 'txnId']
      .where 'network', '=', rewardTransaction.network
      .andWhere 'txnId', '=', rewardTransaction.txnId
      .run()

      cknex().update 'reward_transactions_by_timeUuid'
      .set _.omit rewardTransaction, ['timeBucket', 'timeUuid']
      .where 'timeBucket', '=', rewardTransaction.timeBucket
      .andWhere 'timeUuid', '=', rewardTransaction.timeUuid
      .run()

      cknex().update 'reward_transactions_by_userId'
      .set _.omit rewardTransaction, ['userId', 'timeBucket', 'timeUuid']
      .where 'userId', '=', rewardTransaction.userId
      .andWhere 'timeBucket', '=', rewardTransaction.timeBucket
      .andWhere 'timeUuid', '=', rewardTransaction.timeUuid
      .run()
    ]
    .then ->
      rewardTransaction

  getByNetworkAndTxnId: (network, txnId) ->
    cknex().select '*'
    .from 'reward_transactions'
    .where 'network', '=', network
    .andWhere 'txnId', '=', txnId
    .run {isSingle: true}

  getByUserIdAndTimeBucketAndMinTime: (userId, timeBucket, minTime) ->
    cknex().select '*'
    .from 'reward_transactions_by_userId'
    .where 'userId', '=', userId
    .andWhere 'timeBucket', '=', timeBucket
    .andWhere 'timeUuid', '>', cknex.getTimeUuid minTime
    .run()

module.exports = new RewardTransactionModel()
