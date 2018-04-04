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
        @createKeyspaceIfNotExists 'fortnite'
      ]
      .then =>
        if config.ENV is config.ENVS.DEV
          createTables = _.map _.filter(tables, ({name}) ->
            name in [
              'polls_by_id'
              'polls_by_groupId'
              'poll_votes_by_pollId'
              'poll_votes_by_userId'
              'poll_votes_by_pollId'
              # 'auto_refresh_playerIds'
              # 'user_blocks_by_userId'
              # 'lfg_by_groupId_and_userId'
              # 'lfg_by_groupId'
              # 'group_pages_by_groupId'
              # 'user_followers_by_followedId'
              # 'user_followers_by_userId_sort_time'
              # 'user_followers_by_followedId_sort_time'
              # 'user_followers_counter'
              # 'user_following_counter'
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
