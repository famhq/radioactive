_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

Thread = require '../models/thread'
ThreadComment = require '../models/thread_comment'
ThreadVote = require '../models/thread_vote'
Ban = require '../models/ban'
ProfanityService = require '../services/profanity'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
config = require '../config'

creatorId = [
  EmbedService.TYPES.THREAD_COMMENT.CREATOR
  EmbedService.TYPES.THREAD_COMMENT.TIME
]

MAX_LENGTH = 5000
TEN_MINUTES_SECONDS = 60 * 10
MAX_COMMENT_DEPTH = 3

# there's probably a cleaner / more efficial way to this
getCommentsTree = (comments, findParentId, options) ->
  options ?= {}
  {depth, sort, skip, limit, getUnmatched} = options
  depth ?= 0
  limit ?= 50
  skip ?= 0

  if depth > MAX_COMMENT_DEPTH
    return {comments: [], unmatched: comments}

  {matchedComments, unmatched} = _.groupBy comments, ({parentId}) ->
    if "#{parentId}" is "#{findParentId}"
    then 'matchedComments'
    else 'unmatched'

  commentsTree = _.map matchedComments, (comment) ->
    # for each map step, reduce size of unmatched
    {comments, unmatched} = getCommentsTree(
      unmatched, comment.id, _.defaults {
        depth: depth + 1
        skip: 0
        getUnmatched: true
      }, options
    )
    comment.children = comments
    comment

  if sort is 'popular'
    comments = _.orderBy commentsTree, ({upvotes, downvotes}) ->
      upvotes - downvotes
    , 'desc'
  else
    comments = _.reverse commentsTree

  if getUnmatched
    {comments, unmatched}
  else
    comments

embedMyVotes = (comments, commentVotes) ->
  _.map comments, (comment) ->
    comment.myVote = _.find commentVotes, ({parentId}) ->
      "#{parentId}" is "#{comment.id}"
    comment.children = embedMyVotes comment.children, commentVotes
    comment

class ThreadCommentCtrl
  checkIfBanned: (groupId, ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByGroupIdAndIp groupId, ipAddr, {preferCache: true}
      Ban.getByGroupIdAndUserId groupId, userId, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId]) ->
      if bannedIp?.ip or bannedUserId?.userId
        router.throw status: 403, 'unable to post'

  create: ({body, threadId, parentId, parentType}, {user, headers, connection}) =>
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

    @checkIfBanned config.EMPTY_UUID, ip, user.id, router
    .then ->
      ThreadComment.upsert
        creatorId: user.id
        body: body
        threadId: threadId
        parentId: parentId
        parentType: parentType
    .tap ->
      Thread.updateById parentId, {lastUpdateTime: new Date()}

  getAllByThreadId: ({threadId, sort, skip, limit}, {user}) ->
    sort ?= 'popular'
    skip ?= 0
    prefix = CacheService.PREFIXES.THREAD_COMMENTS_THREAD_ID
    key = "#{prefix}:#{threadId}:#{sort}"
    CacheService.preferCache key, ->
      ThreadComment.getAllByThreadId threadId, {preferCache: true}
      .map EmbedService.embed {embed: creatorId}
      .then (allComments) ->
        getCommentsTree allComments, threadId, {sort, skip, limit}
    , {expireSeconds: TEN_MINUTES_SECONDS}
    .then (comments) ->
      comments = comments?.slice skip, skip + limit
      ThreadVote.getAllByCreatorIdAndParentTopId user.id, threadId
      .then (commentVotes) ->
        embedMyVotes comments, commentVotes

  flag: ({id}, {headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    # TODO
    ThreadComment.getById id
    .then EmbedService.embed {
      embed: [EmbedService.TYPES.THREAD_COMMENT.CREATOR]
    }

module.exports = new ThreadCommentCtrl()
