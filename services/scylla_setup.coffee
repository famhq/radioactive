Promise = require 'bluebird'

cknex = require './cknex'
config = require '../config'

# TODO

class ScyllaSetupService
  setup: (tables) =>
    @createKeyspaceIfNotExists config.RETHINK.DB
    Promise.map tables, (table) =>
      @createTableIfNotExist table.name, table.options

  createKeyspaceIfNotExists: (dbName) ->
    # cknex.createKeyspaceIfNotExists

  createTableIfNotExist: (tableName, options) ->
    # cknex.createColumnFamilyIfNotExists


module.exports = new ScyllaSetupService()
