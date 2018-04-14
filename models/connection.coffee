_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
cknex = require '../services/cknex'
CacheService = require '../services/cache'

defaultConnection = (connection) ->
  unless connection?
    return null

  connection.data = JSON.stringify connection.data
  connection.lastUpdateTime = new Date()

  connection

defaultConnectionOutput = (connection) ->
  unless connection?
    return null

  if connection.data
    connection.data = try
      JSON.parse connection.data
    catch err
      {}

  connection

tables = [
  {
    name: 'connections_by_userId'
    keyspace: 'starfire'
    fields:
      site: 'text'
      userId: 'uuid'
      token: 'text'
      data: 'text'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['site']
  }
]

class ConnectionModel
  SCYLLA_TABLES: tables

  upsert: (connection) ->
    connection = defaultConnection connection
    cknex().update 'connections_by_userId'
    .set _.omit connection, ['userId', 'site']
    .where 'userId', '=', connection.userId
    .andWhere 'site', '=', connection.site
    .run()

  getAllByUserId: (userId) =>
    cknex().select '*'
    .from 'connections_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultConnectionOutput

  getByUserIdAndSite: (userId, action) =>
    cknex().select '*'
    .from 'connections_by_userId'
    .where 'userId', '=', userId
    .andWhere 'site', '=', site
    .run {isSingle: true}
    .then defaultConnectionOutput

module.exports = new ConnectionModel()
