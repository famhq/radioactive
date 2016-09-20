log = require 'loga'

config = require '../config'
server = require '../index'

DB = config.RETHINK.DB
HOST = config.RETHINK.HOST

r = require('rethinkdbdash')
  host: HOST
  db: DB

before ->
  unless config.VERBOSE
    log.level = null

  truncateTables = ->
    r.dbList()
    .contains DB
    .do (result) ->
      r.branch result,
        r.tableList()
        .forEach( (table) ->
          r.table(table).delete()
        ),
        {dopped: 0}
    .run()

  dropIndexes = ->
    r.dbList()
    .contains DB
    .do (result) ->
      r.branch result,
        r.tableList()
        .forEach( (table) ->
          r.table(table).indexList().forEach (index) ->
            r.table(table).indexDrop index
        ),
        {dopped: 0}
    .run()

  Promise.all [
    truncateTables()
    dropIndexes()
  ]
  .then server.setup
