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
      sourceId: 'text'
      token: 'text'
      data: 'text'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['site']
  }
  {
    name: 'connections_by_site_and_sourceId'
    keyspace: 'starfire'
    fields:
      site: 'text'
      userId: 'uuid'
      sourceId: 'text'
      token: 'text'
      data: 'text'
      lastUpdateTime: 'timestamp'
    primaryKey:
      partitionKey: ['site', 'sourceId']
      clusteringColumns: null
  }
]

class ConnectionModel
  SCYLLA_TABLES: tables

  upsert: (connection) ->
    connection = defaultConnection connection
    Promise.all [
      cknex().update 'connections_by_userId'
      .set _.omit connection, ['userId', 'site']
      .where 'userId', '=', connection.userId
      .andWhere 'site', '=', connection.site
      .run()

      cknex().update 'connections_by_site_and_sourceId'
      .set _.omit connection, ['site', 'sourceId']
      .where 'site', '=', connection.site
      .andWhere 'sourceId', '=', connection.sourceId
      .run()
    ]

  getAllByUserId: (userId) =>
    cknex().select '*'
    .from 'connections_by_userId'
    .where 'userId', '=', userId
    .run()
    .map defaultConnectionOutput

  getByUserIdAndSite: (userId, site) =>
    cknex().select '*'
    .from 'connections_by_userId'
    .where 'userId', '=', userId
    .andWhere 'site', '=', site
    .run {isSingle: true}
    .then defaultConnectionOutput

  getBySiteAndSourceId: (site, sourceId) =>
    cknex().select '*'
    .from 'connections_by_site_and_sourceId'
    .where 'site', '=', site
    .andWhere 'sourceId', '=', sourceId
    .run {isSingle: true}
    .then defaultConnectionOutput

module.exports = new ConnectionModel()
