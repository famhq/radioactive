_ = require 'lodash'
router = require 'exoid-router'

ThreadComment = require '../models/thread_comment'
Thread = require '../models/thread'
Ban = require '../models/ban'
EmbedService = require '../services/embed'
config = require '../config'

creatorId = [EmbedService.TYPES.THREAD_COMMENT.CREATOR]

class ThreadCommentCtrl
  checkIfBanned: (ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByIp ipAddr, {preferCache: true}
      Ban.getByUserId userId, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId]) ->
      if bannedIp?.ip or bannedUserId?.userId
        router.throw status: 403, 'unable to post'

  create: ({body, parentId, parentType}, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    body = body.trim()

    isProfane = ProfanityService.isProfane body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    if body?.length > MAX_LENGTH
      router.throw status: 400, info: 'message is too long...'

    unless body
      router.throw status: 400, info: 'can\'t be empty'

    @checkIfBanned ip, user.id, router
    .then ->
      ThreadComment.create
        creatorId: user.id
        body: body
        parentId: parentId
        parentType: parentType
    .tap ->
      Thread.updateById parentId, {lastUpdateTime: new Date()}

  getAllByParentIdAndParentType: ({parentId, parentType}, {user}) ->
    console.log 'get', parentId, parentType
    ThreadComment.getAllByParentIdAndParentType parentId, parentType
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
