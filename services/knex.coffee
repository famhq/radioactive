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

}

module.exports = knexInstance
