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
    .catch (err) ->
      console.log 'sync err', err
    .then ->
      Promise.map tables, ({tableName, indexes}) ->
        knex('pg_indexes').select()
        .where {tablename: tableName}
        .then (existingIndexes) ->
          knex.schema.table tableName, (table) ->
            _.map indexes, ({columns, type}) ->
              def = "(\"#{columns.join('", "')}\")"
              indexExists = _.find existingIndexes, ({indexdef}) ->
                indexdef.indexOf(def) isnt -1
              if indexExists
                return
              else if type is 'unique'
                table.unique columns
              else
                table.index columns
        .catch (err) ->
          console.log 'index err', err
        # pgadmin
        # just login with radioactive user in pgadmin...
        # GRANT ALL PRIVILEGES ON kinds TO postgres;



module.exports = new PostgresSetupService()
