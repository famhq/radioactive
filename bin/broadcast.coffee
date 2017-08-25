_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

BroadcastService = require '../services/broadcast'
KueRunnerService = require '../services/kue_runner'
PushNotificationService = require '../services/push_notification'
config = require '../config'

IS_TEST_RUN = false
SEND_TO_TOPIC = true
LANG = 'es'
TOPIC = 'es'

###
ideally we'd use fcm console, but it doesn't work with sending the path.
###

# REDIS_HOST=10.123.240.149  RETHINK_HOST=10.123.245.23
# coffee ./bin/broadcast.coffee


UNIQUE_ID = Date.now()
TYPE = PushNotificationService.TYPES.NEWS
# TYPE = PushNotificationService.TYPES.NEWS
lang =
  en:
    title: 'See upcoming shop offers'
    text: 'in the new "More tools" section'
  es:
    title: 'Próximas ofertas de tienda'
    text: 'Toque "shop offers" en "Más herramientas"'
IMAGE_URL = null
# IMAGE_URL = 'https://cdn.wtf/d/images/games/kitten_cards/v2/' +
#              'full_cards/19918_small.png'
DATA = {path: '/addons'}

console.log lang[LANG]
console.log if IS_TEST_RUN then 'TEST in 3' else 'PRODUCTION in 3'

if SEND_TO_TOPIC
  console.log 'topic'
  new Promise (resolve) ->
    setTimeout ->
      PushNotificationService.sendFcm TOPIC, {
        toType: 'topic'
        type: TYPE
        title: lang[LANG].title
        text: lang[LANG].text
        data: DATA
      }
    , 3000
else
  console.log 'single'
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
