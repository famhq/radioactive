_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

BroadcastService = require '../services/broadcast'
KueRunnerService = require '../services/kue_runner'
PushNotificationService = require '../services/push_notification'
config = require '../config'

IS_TEST_RUN = true

# REDIS_HOST=10.123.240.149  RETHINK_HOST=10.123.245.23
# coffee ./bin/broadcast.coffee


UNIQUE_ID = Date.now()
TYPE = PushNotificationService.TYPES.NEWS
# TYPE = PushNotificationService.TYPES.NEWS
# KILL mittens before running this
lang =
  en:
    title: 'The forum!'
    text: 'Have you tried the new forum feature (Spanish only)!'
  es:
    title: 'El Foro'
    text: '¿Has probado la nueva función del foro?'
IMAGE_URL = null
# IMAGE_URL = 'https://cdn.wtf/d/images/games/kitten_cards/v2/' +
#              'full_cards/19918_small.png'
DATA = {path: '/social'} # TODO /forum

console.log if IS_TEST_RUN then 'TEST in 3' else 'PRODUCTION in 3'
new Promise (resolve) ->
  setTimeout ->
    KueRunnerService.listen()
    BroadcastService.broadcast {
      type: TYPE
      lang: lang
      # only spanish users
      # FIXME
      filterLang: 'en'
      data: DATA
      initialDelay: 0
      forceDevSend: true
    }, {isTestRun: IS_TEST_RUN, uniqueId: UNIQUE_ID}
  , 3000
