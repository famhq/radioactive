knex = require 'knex'

config = require '../config'

knexInstance = knex {
  client: 'pg',
  connection: {
    host: config.POSTGRES.HOST
    user: config.POSTGRES.USER
    password: config.POSTGRES.PASS
    database: config.POSTGRES.DB
  }
  useNullAsDefault: true
  debug: false
  pool:
    min: 1
    max: 2 # 4 * 15 replicas is 60 connections. can have up to 100
           # TODO bump up when 100 connection limit is increased
           # https://issuetracker.google.com/issues/37271935
}

module.exports = knexInstance
