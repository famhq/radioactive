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
getCommentsTree = (comments, findParentId, depth = 0, getUnmatched) ->
  if depth > MAX_COMMENT_DEPTH
    return {comments: [], unmatched: comments}

  {matchedComments, unmatched} = _.groupBy comments, ({parentId}) ->
    if "#{parentId}" is "#{findParentId}"
    then 'matchedComments'
    else 'unmatched'

  commentsTree = _.map matchedComments, (comment) ->
    # for each map step, reduce size of unmatched
    {comments, unmatched} = getCommentsTree(
      unmatched, comment.id, depth + 1, true
    )
    comment.children = comments
    comment

  comments = _.orderBy commentsTree, ({upvotes, downvotes}) ->
    upvotes - downvotes
  , 'desc'

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
  checkIfBanned: (ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByIp ipAddr, {preferCache: true}
      Ban.getByUserId userId, {preferCache: true}
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

    @checkIfBanned ip, user.id, router
    .then ->
      ThreadComment.upsert
        creatorId: user.id
        body: body
        threadId: threadId
        parentId: parentId
        parentType: parentType
    .tap ->
      Thread.updateById parentId, {lastUpdateTime: new Date()}

  getAllByThreadId: ({threadId}, {user}) ->
    key = "#{CacheService.PREFIXES.THREAD_COMMENTS_THREAD_ID}:#{threadId}"
    CacheService.preferCache key, ->
      ThreadComment.getAllByThreadId threadId, {preferCache: true}
      .map EmbedService.embed {embed: creatorId}
      .then (allComments) ->
        getCommentsTree allComments, threadId
    , {expireSeconds: TEN_MINUTES_SECONDS}
    .then (comments) ->
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
