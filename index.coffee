fs = require 'fs'
_ = require 'lodash'
log = require 'loga'
cors = require 'cors'
express = require 'express'
Promise = require 'bluebird'
multer = require 'multer'
bodyParser = require 'body-parser'

config = require './config'
routes = require './routes'
r = require './services/rethinkdb'
AuthService = require './services/auth'
CronService = require './services/cron'
KueRunnerService = require './services/kue_runner'
ClashTvService = require './services/clash_tv'

HEALTHCHECK_TIMEOUT = 1000
MAX_FILE_SIZE_BYTES = 20 * 1000 * 1000 # 20MB
MAX_FIELD_SIZE_BYTES = 100 * 1000 # 100KB


# Setup rethinkdb
createDatabaseIfNotExist = (dbName) ->
  r.dbList()
  .contains dbName
  .do (result) ->
    r.branch result,
      {created: 0},
      r.dbCreate dbName
  .run()

createTableIfNotExist = (tableName, options) ->
  r.tableList()
  .contains tableName
  .do (result) ->
    r.branch result,
      {created: 0},
      r.tableCreate tableName, options
  .run()

createIndexIfNotExist = (tableName, indexName, indexFn, indexOpts) ->
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

setup = ->
  createDatabaseIfNotExist config.RETHINK.DB
  .then ->
    Promise.map fs.readdirSync('./models'), (modelFile) ->
      model = require('./models/' + modelFile)
      tables = model?.RETHINK_TABLES or []

      Promise.map tables, (table) ->
        createTableIfNotExist table.name, table.options
        .then ->
          Promise.map (table.indexes or []), ({name, fn, options}) ->
            fn ?= null
            createIndexIfNotExist table.name, name, fn, options
        .then ->
          r.table(table.name).indexWait().run()
  .tap ->
    CronService.start()
    KueRunnerService.listen()

    null

app = express()

app.set 'x-powered-by', false

app.use cors()

# Before BodyParser middleware to preserve file stream
upload = multer
  limits:
    fields: 10
    fieldSize: MAX_FIELD_SIZE_BYTES
    fileSize: MAX_FILE_SIZE_BYTES
    files: 1

app.post '/upload', (req, res, next) ->
  schema = Joi.object().keys
    path: Joi.string()
    body: Joi.string().optional()
  .unknown()

  valid = Joi.validate req.query, schema, {presence: 'required', convert: false}

  if valid.error?
    log.error
      event: 'error'
      status: 400
      info: 'invalid /upload parameters'
      error: valid.error
    return res.status(400).json {status: 400, info: 'invalid upload parameters'}

  try
    path = req.query.path
    body = JSON.parse req.query.body or '{}'
  catch err
    log.error
      event: 'error'
      status: 400
      info: 'invalid /upload parameters'
      error: err
    return res.status(400).json {status: 400, info: 'invalid upload parameters'}

  new Promise (resolve, reject) ->
    upload.single('file') req, res, (err) ->
      if err
        return reject err
      resolve()
  .then ->
    routes.resolve path, body, req
  .then ({result, error, cache}) ->
    if error?
      res.status(error.status or 500).json error
    else
      res.json result
  .catch (err) ->
    log.error err
    next err


app.use bodyParser.json()
# Avoid CORS preflight
app.use bodyParser.json({type: 'text/plain'})
app.use AuthService.middleware

app.get '/ping', (req, res) -> res.send 'pong'

app.get '/healthcheck', (req, res, next) ->
  Promise.settle [
    r.dbList().run().timeout HEALTHCHECK_TIMEOUT
  ]
  .spread (rethinkdb) ->
    result =
      rethinkdb: rethinkdb.isFulfilled()

    result.healthy = _.every _.values result
    return result
  .then (status) ->
    res.json status
  .catch next

app.post '/log', (req, res) ->
  unless req.body?.event is 'client_error'
    return res.status(400).send 'must be type client_error'

  log.warn req.body
  res.status(204).send()

app.post '/exoid', routes.asMiddleware()
app.get '/clashTv', (req, res) -> ClashTvService.process()

module.exports = {
  app
  setup
}
