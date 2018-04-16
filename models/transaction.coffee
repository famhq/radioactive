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
    name: 'transactions'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      amountCents: 'int'
      isCompleted: 'boolean'
      isFromPending: 'boolean'
    primaryKey:
      partitionKey: ['id']
  }
]
class TransactionModel
  SCYLLA_TABLES: tables

  upsert: (transaction) ->
    transaction = defaultTransaction transaction

    cknex().update 'transactions'
    .set _.omit transaction, ['id']
    .where 'id', '=', transaction.id
    .run()

  getById: (id) ->
    cknex().select '*'
    .from 'transactions'
    .where 'groupId', '=', groupId
    .run {isSingle: true}
    .then defaultTransactionOutput



module.exports = new TransactionModel()
