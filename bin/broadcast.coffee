_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

BroadcastService = require '../services/broadcast'
KueRunnerService = require '../services/kue_runner'
PushNotificationService = require '../services/push_notification'
config = require '../config'

IS_TEST_RUN = true

# REDIS_HOST=10.39.244.97  RETHINK_HOST=10.39.246.151
# coffee ./bin/broadcast.coffee


UNIQUE_ID = Date.now()
TYPE = PushNotificationService.TYPES.NEWS
# TYPE = PushNotificationService.TYPES.NEWS
# KILL mittens before running this
TITLE = 'New feature!'
MESSAGE = 'See how your deck win rates compare to the community\'s averages in
the profile history tab!'
IMAGE_URL = null
# IMAGE_URL = 'https://cdn.wtf/d/images/games/kitten_cards/v2/' +
#              'full_cards/19918_small.png'
DATA = {path: '/profile'}

console.log if IS_TEST_RUN then 'TEST in 3' else 'PRODUCTION in 3'
new Promise (resolve) ->
  setTimeout ->
    KueRunnerService.listen()
    BroadcastService.broadcast {
      title: TITLE
      type: TYPE
      text: MESSAGE
      data: DATA
      initialDelay: 0
      forceDevSend: true
    }, {isTestRun: IS_TEST_RUN, uniqueId: UNIQUE_ID}
  , 3000
