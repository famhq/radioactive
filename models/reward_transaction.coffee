_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'

ONE_DAY_SECONDS = 3600 * 24

defaultRewardTransaction = (rewardTransaction) ->
  unless rewardTransaction?
    return null

  _.defaults rewardTransaction, {
    time: new Date()
  }


tables = [
  {
    name: 'reward_transactions_by_id'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      userId: 'uuid'
      transactionId: 'text'
      network: 'text'
      amountCents: 'int'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
]

class RewardTransactionModel
  SCYLLA_TABLES: tables

  upsert: (rewardTransaction) ->
    rewardTransaction = defaultRewardTransaction rewardTransaction

    cknex().update 'reward_transactions_by_id'
    .set _.omit rewardTransaction, ['id']
    .where 'id', '=', rewardTransaction.id
    .run()
    .then ->
      rewardTransaction

module.exports = new RewardTransactionModel()
