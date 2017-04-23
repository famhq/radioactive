Promise = require 'bluebird'

r = require './rethinkdb'
config = require '../config'

class RethinkSetupService
  setup: (tables) =>
    @createDatabaseIfNotExist config.RETHINK.DB
    Promise.map tables, (table) =>
      @createTableIfNotExist table.name, table.options
      .then =>
        Promise.map (table.indexes or []), ({name, fn, options}) =>
          fn ?= null
          @createIndexIfNotExist(
            table.name, name, fn, options
          )
      .then ->
        r.table(table.name).indexWait().run()

  # Setup rethinkdb
  createDatabaseIfNotExist: (dbName) ->
    r.dbList()
    .contains dbName
    .do (result) ->
      r.branch result,
        {created: 0},
        r.dbCreate dbName
    .run()

  createTableIfNotExist: (tableName, options) ->
    r.tableList()
    .contains tableName
    .do (result) ->
      r.branch result,
        {created: 0},
        r.tableCreate tableName, options
    .run()

  createIndexIfNotExist: (tableName, indexName, indexFn, indexOpts) ->
    r.table tableName
    .indexList()
    .contains indexName
    .run() # can't use r.branch() with r.row() compound indexes
    .then (isCreated) ->
      unless isCreated
        (if indexFn?
          r.table tableName
          .indexCreate indexName, indexFn, indexOpts
        else
          r.table tableName
          .indexCreate indexName, indexOpts
        ).run()

module.exports = new RethinkSetupService()
