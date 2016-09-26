_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
UserData = require '../models/user_data'
ThreadMessage = require '../models/thread_message'
Thread = require '../models/thread'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CHAT_MESSAGE.USER]

MAX_CONVERSATION_USER_IDS = 20

defaultUserEmbed = [EmbedService.TYPES.USER.DATA]

class ThreadMessageCtrl
  create: ({body, threadId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    if user.flags.isChatBanned
      router.throw status: 400, detail: 'unable to post...'

    ThreadMessage.create
      userId: user.id
      body: body
      threadId: threadId
    .tap ->
      Thread.updateById threadId, {lastUpdateTime: new Date()}

module.exports = new ThreadMessageCtrl()
