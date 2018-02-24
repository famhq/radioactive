Promise = require 'bluebird'
_ = require 'lodash'

CacheService = require './cache'
cknex = require './cknex'
config = require '../config'

# TODO

class ScyllaSetupService
  setup: (tables) =>
    CacheService.runOnce 'scylla_setup5', =>
      Promise.all [
        @createKeyspaceIfNotExists 'starfire'
        @createKeyspaceIfNotExists 'clash_royale'
      ]
      .then =>
        if config.ENV is config.ENVS.DEV
          createTables = _.map _.filter(tables, ({name}) ->
            name in [
              # 'matches_by_playerId'
              'group_users_online'
              # 'addons_by_key'
              # 'addons_by_id'
              # 'addons_by_gameKey'
              # 'addon_votes_by_creatorId'
            ]
          )
          Promise.each createTables, @createTableIfNotExist
        else
          Promise.each tables, @createTableIfNotExist
    , {expireSeconds: 300}

  createKeyspaceIfNotExists: (keyspaceName) ->
    # TODO
    ###
    CREATE KEYSPACE clash_royale WITH replication = {
      'class': 'NetworkTopologyStrategy', 'datacenter1': '3'
    } AND durable_writes = true;
    CREATE KEYSPACE fortnite WITH replication = {
      'class': 'NetworkTopologyStrategy', 'datacenter1': '3'
    } AND durable_writes = true;
    CREATE KEYSPACE starfire WITH replication = {
      'class': 'NetworkTopologyStrategy', 'datacenter1': '3'
    } AND durable_writes = true;
    ###
    Promise.resolve null

  createTableIfNotExist: (table) ->
    q = cknex(table.keyspace).createColumnFamilyIfNotExists table.name
    _.map table.fields, (type, key) ->
      if typeof type is 'object'
        if type.subType2
          q[type.type] key, type.subType, type.subType2
        else
          q[type.type] key, type.subType
      else
        try
          q[type] key
        catch err
          console.log key
          throw err

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
