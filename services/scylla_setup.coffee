Promise = require 'bluebird'
_ = require 'lodash'

CacheService = require './cache'
cknex = require './cknex'
config = require '../config'

# TODO

class ScyllaSetupService
  setup: (tables) =>
    CacheService.runOnce 'scylla_setup', =>
      @createKeyspaceIfNotExists config.SCYLLA.KEYSPACE
      .then =>
        Promise.each tables, @createTableIfNotExist
    , {expireSeconds: 300}

  createKeyspaceIfNotExists: (keyspaceName) ->
    # TODO
    Promise.resolve null

  createTableIfNotExist: (table) ->
    q = cknex().createColumnFamilyIfNotExists table.name
    _.map table.fields, (type, key) ->
      q[type] key

    if table.primaryKey.clusteringColumns
      q.primary(
        table.primaryKey.partitionKey, table.primaryKey.clusteringColumns
      )
    else
      q.primary table.primaryKey.partitionKey

    if table.withClusteringOrderBy
      q.withClusteringOrderBy(
        table.withClusteringOrderBy[0]
        table.withClusteringOrderBy[1]
      )
    q.run()

module.exports = new ScyllaSetupService()
