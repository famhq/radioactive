_ = require 'lodash'
router = require 'exoid-router'

ThreadMessage = require '../models/thread_message'
Thread = require '../models/thread'
EmbedService = require '../services/embed'
config = require '../config'

MAX_CONVERSATION_USER_IDS = 20

class ThreadMessageCtrl
  create: ({body, threadId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    if user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    ThreadMessage.create
      userId: user.id
      body: body
      threadId: threadId
    .tap ->
      Thread.updateById threadId, {lastUpdateTime: new Date()}

  flag: ({id}, {headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    ThreadMessage.getById id
    .then EmbedService.embed [EmbedService.TYPES.THREAD_MESSAGE.USER]
    .then (threadMessage) ->
      flagIps = threadMessage.flagIps or []
      if flagIps.indexOf(ip) is -1
        ThreadMessage.updateById threadMessage.id, {
          flags: (threadMessage.flags or []).concat [1]
          flagIps: flagIps.concat [ip]
        }

module.exports = new ThreadMessageCtrl()
