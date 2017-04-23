Promise = require 'bluebird'
Manager = require 'knex-schema'
_ = require 'lodash'

knex = require './knex'
config = require '../config'

class PostgresSetupService
  # Setup rethinkdb
  setup: (tables) ->
    manager = new Manager knex
    syncTables = _.map tables, ({tableName, fields}) ->
      {
        tableName: tableName
        build: (table) ->
          _.forEach fields, (field) ->
            if field.type is 'array'
              column = table.specificType field.name, "#{field.arrayType}[]"
            else
              column = table[field.type](field.name, field.length)
            if field.index is 'primary'
              column.primary()
            else if field.index is 'unique'
              column.unique()
            else if field.index is 'gin'
              column.index null, 'gin'
            else if field.index is 'default'
              column.index()
      }
    manager.sync syncTables
    .then ->
      Promise.map tables, ({tableName, indexes}) ->
        knex.schema.table tableName, (table) ->
          Promise.map indexes, ({columns}) ->
            table.index columns


module.exports = new PostgresSetupService()
