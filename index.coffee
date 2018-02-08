fs = require 'fs'
_ = require 'lodash'
log = require 'loga'
cors = require 'cors'
express = require 'express'
Promise = require 'bluebird'
multer = require 'multer'
bodyParser = require 'body-parser'
cluster = require 'cluster'
http = require 'http'
socketIO = require 'socket.io'
# socketIORedis = require 'socket.io-redis'
Redis = require 'ioredis'
# memwatch = require 'memwatch-next'
#
# hd = undefined
# snapshotTaken = false
# memwatch.on 'stats', (stats) ->
#   # console.log 'stats:', stats
#   if snapshotTaken is false
#     hd = new (memwatch.HeapDiff)
#     snapshotTaken = true
#   else
#     # diff = hd.end()
#     snapshotTaken = false
#     # console.log(JSON.stringify(diff, null, '\t'))
#   return
# memwatch.on 'leak', (info) ->
#   console.log 'leak:', info
#   diff = hd.end()
#   hd = new (memwatch.HeapDiff)
#   snapshotTaken = false
#   console.log(JSON.stringify(diff, null, '\t'))
#   return


Joi = require 'joi'

config = require './config'
routes = require './routes'
r = require './services/rethinkdb'
cknex = require './services/cknex'
RethinkSetupService = require './services/rethink_setup'
PostgresSetupService = require './services/postgres_setup'
ScyllaSetupService = require './services/scylla_setup'
AuthService = require './services/auth'
CronService = require './services/cron'
KueRunnerService = require './services/kue_runner'
ChatMessageCtrl = require './controllers/chat_message'
ClashRoyaleAPICtrl = require './controllers/clash_royale_api'
ClashRoyaleDeckCtrl = require './controllers/clash_royale_deck'
RewardCtrl = require './controllers/reward'
HealthCtrl = require './controllers/health'
VideoDiscoveryService = require './services/video_discovery'
StreamService = require './services/stream'
ClashRoyaleDeck = require './models/clash_royale_deck'
ClashRoyaleCard = require './models/clash_royale_card'
ForumSigPage = require './dynamic_images/pages/forum_sig'
ChestCyclePage = require './dynamic_images/pages/chest_cycle'

if config.DEV_USE_HTTPS
  https = require 'https'
  fs = require 'fs'
  privateKey  = fs.readFileSync './bin/starfire-dev.key'
  certificate = fs.readFileSync './bin/starfire-dev.crt'
  credentials = {key: privateKey, cert: certificate}

MAX_FILE_SIZE_BYTES = 20 * 1000 * 1000 # 20MB
MAX_FIELD_SIZE_BYTES = 100 * 1000 # 100KB

Promise.config {warnings: false}

setup = ->
  models = fs.readdirSync('./models')
  rethinkTables = _.flatten _.map models, (modelFile) ->
    model = require('./models/' + modelFile)
    model?.RETHINK_TABLES or []
  postgresTables = _.flatten _.map models, (modelFile) ->
    model = require('./models/' + modelFile)
    model?.POSTGRES_TABLES or []
  scyllaTables = _.flatten _.map models, (modelFile) ->
    model = require('./models/' + modelFile)
    model?.SCYLLA_TABLES or []

  Promise.all [
    RethinkSetupService.setup rethinkTables
    .then -> console.log 'rethink setup'
    PostgresSetupService.setup postgresTables
    .then -> console.log 'postgres setup'
    ScyllaSetupService.setup scyllaTables
    .then -> console.log 'scylla setup'
  ]
  .catch (err) ->
    console.log 'setup', err
  .tap ->
    CronService.start()
    KueRunnerService.listen()
    null # don't block

childSetup = ->
  KueRunnerService.listen()
  return Promise.resolve null # don't block

app = express()

app.set 'x-powered-by', false

app.use cors()
app.use AuthService.middleware

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


app.use bodyParser.json({limit: '1mb'})
# Avoid CORS preflight
app.use bodyParser.json({type: 'text/plain', limit: '1mb'})
app.use bodyParser.urlencoded {extended: true} # Kiip uses

app.get '/', (req, res) -> res.status(200).send 'ok'

app.get '/ping', (req, res) -> res.send 'pong'

app.get '/healthcheck', HealthCtrl.check

app.get '/healthcheck/throw', HealthCtrl.checkThrow

app.post '/reward/:network', RewardCtrl.process
app.get '/reward/:network', RewardCtrl.process

app.post '/log', (req, res) ->
  unless req.body?.event is 'client_error'
    return res.status(400).send 'must be type client_error'

  log.warn req.body
  res.status(204).send()

app.post '/chatMessage/:id/card', ChatMessageCtrl.updateCard

app.post '/clashRoyaleApi/updatePlayerMatches', (req, res) ->
  ClashRoyaleAPICtrl.updatePlayerMatches req, res
  .then ->
    res.status(200).send()

app.post '/clashRoyaleApi/updatePlayerData', (req, res) ->
  ClashRoyaleAPICtrl.updatePlayerData req, res
  .then ->
    res.status(200).send()

app.post '/clashRoyaleApi/updateClan', (req, res) ->
  ClashRoyaleAPICtrl.updateClan req, res
  .then ->
    res.status(200).send()

app.get '/updateTopPlayers', (req, res) ->
  ClashRoyaleAPICtrl.updateTopPlayers req, res
  res.status(200).send()

app.get '/top200Decks', (req, res) ->
  ClashRoyaleAPICtrl.top200Decks req, res

app.get '/top2v2Decks', (req, res) ->
  ClashRoyaleDeckCtrl.getPopular {gameType: '2v2'}
  .then (decks) ->
    decks = _.map decks, (deck) ->
      winRate = _.find(deck.stats, {gameType: '2v2'})?.winRate
      winRate = Math.round(winRate * 100 * 100) / 100
      {
        card: deck.deckId
        matchCount: deck.matchCount
        winRate: "#{winRate}%"
      }
    res.status(200).send decks

app.get '/topTouchdown', (req, res) ->
  ClashRoyaleCard.getTop {gameType: 'touchdown2v2Draft'}
  .then (cards) ->
    cards = _.map cards, (card) ->
      winRate = card.winRate * 100
      roundedWinRate = Math.round(winRate * 100) / 100
      "#{card.cardId}: #{roundedWinRate}%"
    res.status(200).send cards

app.get '/queueTop200', (req, res) ->
  ClashRoyaleAPICtrl.queueTop200 req, res
  res.status(200).send()

app.get '/updateAutoRefreshDebug', (req, res) ->
  ClashRoyaleAPICtrl.updateAutoRefreshDebug()
  res.status(200).send()

app.get '/videoDiscovery', (req, res) ->
  VideoDiscoveryService.discover()
  res.status(200).send()

app.get '/migrateConversations', (req, res) ->
  Conversation = require './models/conversation'
  Conversation.migrateAll()
  res.status(200).send()

app.get '/migratePushTokens', (req, res) ->
  PushToken = require './models/push_token'
  PushToken.migrateAll()
  res.status(200).send()

app.get '/migrateUserPlayers', (req, res) ->
  UserPlayer = require './models/user_player'
  UserPlayer.migrateAll()
  res.status(200).send()

app.get '/cleanKueFailed', (req, res) ->
  KueCreateService = require './services/kue_create'
  KueCreateService.clean()
  .catch ->
    console.log 'kue clean route fail'
  res.sendStatus 200

app.get '/di/crForumSig/:userId.png', (req, res) ->
  $page = new ForumSigPage {req, res}

  res.setHeader 'Content-Type', 'image/png'
  $page.render()
  .then (buffer) ->
    res.status(200).send buffer

app.get '/di/crChestCycle/:playerId.png', (req, res) ->
  $page = new ChestCyclePage {req, res}

  res.setHeader 'Content-Type', 'image/png'
  $page.render()
  .then (buffer) ->
    res.status(200).send buffer

# for now, this is unnecessary. lightning-rod is clientip,
# and stickCluster handles the cpus
# if config.REDIS.NODES.length > 1
#   redisPub = new Redis.Cluster _.filter(config.REDIS.NODES)
#   redisSub = new Redis.Cluster _.filter(config.REDIS.NODES), {
#     return_buffers: true
#   }
# else
#   redisPub = new Redis {
#     port: config.REDIS.PORT
#     host: config.REDIS.NODES[0]
#   }
#   redisSub = new Redis {
#     port: config.REDIS.PORT
#     host: config.REDIS.NODES[0]
#     return_buffers: true
#   }

server = if config.DEV_USE_HTTPS \
         then https.createServer credentials, app
         else http.createServer app
io = socketIO.listen server
# FIXME: fix socket.io not working for client (works for server)
# after a period of time (8 hours).
# Test: go to decks page first, then home tab. see if it loads
#
# *might* be one of rethinkdb-proxies crashing, but server
# hits different pod so it works?
setInterval ->
  console.log 'socket.io', io.engine.clientsCount
, 10000

# for now, this is unnecessary. lightning-rod is clientip,
# and stickCluster handles the cpus
# io.adapter socketIORedis {
#   pubClient: redisPub
#   subClient: redisSub
#   subEvent: config.REDIS.PREFIX + 'socketio:message'
# }
routes.setMiddleware AuthService.exoidMiddleware
routes.setDisconnect StreamService.exoidDisconnect
io.on 'connection', routes.onConnection

module.exports = {
  server
  setup
  childSetup
}
