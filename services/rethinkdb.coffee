config = require '../config'

DB = config.RETHINK.DB
HOST = config.RETHINK.HOST

r = require('rethinkdbdash')
  host: HOST
  db: DB

module.exports = r
