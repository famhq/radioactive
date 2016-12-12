_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'

TRANSACTION_ID_INDEX = 'transactionId'

defaultTransaction = (transaction) ->
  unless transaction?
    return null

  _.defaults transaction, {
    id: uuid.v4()
    userId: null
    time: new Date()
    amount: 0.00
    productId: null
    isCompleted: false
    isFromPending: false
  }

TRANSACTIONS_TABLE = 'transactions'

class TransactionModel
  RETHINK_TABLES: [
    {
      name: TRANSACTIONS_TABLE
      indexes: [
        {
          name: TRANSACTION_ID_INDEX
        }
      ]
    }
  ]

  create: (transaction) ->
    transaction = defaultTransaction transaction

    r.table TRANSACTIONS_TABLE
    .insert transaction
    .run()
    .then ->
      transaction

  getByTransactionId: (transactionId) ->
    r.table TRANSACTIONS_TABLE
    .getAll transactionId, {index: TRANSACTION_ID_INDEX}
    .filter {isCompleted: true}
    .nth 0
    .default null
    .run()



module.exports = new TransactionModel()
