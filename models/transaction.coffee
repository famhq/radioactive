_ = require 'lodash'

cknex = require '../services/cknex'

defaultTransaction = (transaction) ->
  unless transaction?
    return null

  _.defaults transaction, {
    id: cknex.getTimeUuid()
    amountCents: 0
    isCompleted: false
    isFromPending: false
  }

defaultTransactionOutput: (transaction) ->
  transaction.time = transaction.id.getDate()
  transaction

tables = [
  {
    name: 'transactions_by_userId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      iapKey: 'text'
      amountCents: 'int'
      isCompleted: 'boolean'
      isFromPending: 'boolean'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['id']
  }
  {
    name: 'transactions_by_id'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      iapKey: 'text'
      amountCents: 'int'
      isCompleted: 'boolean'
      isFromPending: 'boolean'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
]
class TransactionModel
  SCYLLA_TABLES: tables

  upsert: (transaction) ->
    transaction = defaultTransaction transaction

    Promise.all [
      cknex().update 'transactions_by_userId'
      .set _.omit transaction, ['userId', 'id']
      .where 'userId', '=', transaction.userId
      .andWhere 'id', '=', transaction.id
      .run()

      cknex().update 'transactions_by_id'
      .set _.omit transaction, ['id']
      .where 'id', '=', transaction.id
      .run()
    ]

  getById: (id) ->
    cknex().select '*'
    .from 'transactions_by_id'
    .where 'id', '=', id
    .run {isSingle: true}
    .then defaultTransactionOutput



module.exports = new TransactionModel()
