_ = require 'lodash'

cknex = require '../services/cknex'

defaultUserPrivateData = (userPrivateData) ->
  unless userPrivateData?
    return null

  if userPrivateData.data
    userPrivateData.data = JSON.stringify userPrivateData.data

  userPrivateData

defaultUserPrivateDataOutput = (userPrivateData) ->
  userPrivateData.data = try
    JSON.parse userPrivateData.data
  catch err
    {}
  userPrivateData

tables = [
  {
    name: 'user_private_data'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      data: 'text'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: null
  }
]
class UserPrivateDataModel
  SCYLLA_TABLES: tables

  upsert: (userPrivateData) ->
    userPrivateData = defaultUserPrivateData userPrivateData

    cknex().update 'user_private_data'
    .set _.omit userPrivateData, ['userId']
    .where 'userId', '=', userPrivateData.userId
    .run()

  getByUserId: (userId) ->
    cknex().select '*'
    .from 'user_private_data'
    .where 'userId', '=', userId
    .run {isSingle: true}
    .then defaultUserPrivateDataOutput



module.exports = new UserPrivateDataModel()
