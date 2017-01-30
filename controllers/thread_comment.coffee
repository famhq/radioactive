_ = require 'lodash'
router = require 'exoid-router'

ThreadComment = require '../models/thread_comment'
Thread = require '../models/thread'
EmbedService = require '../services/embed'
config = require '../config'

creatorId = [EmbedService.TYPES.THREAD_COMMENT.CREATOR]

class ThreadCommentCtrl
  create: ({body, threadId}, {user, headers, connection}) ->
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    if user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    ThreadComment.create
      creatorId: user.id
      body: body
      threadId: threadId
    .tap ->
      Thread.updateById threadId, {lastUpdateTime: new Date()}

  getAllByThreadId: ({threadId}, {user}) ->
    ThreadComment.getAllByThreadId threadId
    .map EmbedService.embed {embed: creatorId}

  flag: ({id}, {headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    ThreadComment.getById id
    .then EmbedService.embed {embed: [EmbedService.TYPES.THREAD_COMMENT.CREATOR]}
    .then (threadComment) ->
      flagIps = threadComment.flagIps or []
      if flagIps.indexOf(ip) is -1
        ThreadComment.updateById threadComment.id, {
          flags: (threadComment.flags or []).concat [1]
          flagIps: flagIps.concat [ip]
        }

module.exports = new ThreadCommentCtrl()
