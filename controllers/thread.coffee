_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
request = require 'request-promise'
uuid = require 'uuid'

User = require '../models/user'
UserData = require '../models/user_data'
Group = require '../models/group'
GroupUser = require '../models/group_user'
Thread = require '../models/thread'
ThreadVote = require '../models/thread_vote'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Ban = require '../models/ban'
ProfanityService = require '../services/profanity'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
ImageService = require '../services/image'
r = require '../services/rethinkdb'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.THREAD.CREATOR
  EmbedService.TYPES.THREAD.COMMENT_COUNT
]
playerDeckEmbed = [
  EmbedService.TYPES.THREAD.PLAYER_DECK
]

MAX_LENGTH = 5000
ONE_MINUTE_SECONDS = 60
IMAGE_REGEX = /\!\[(.*?)\]\((.*?)\)/gi
YOUTUBE_ID_REGEX = ///
  (?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)
  ([^"&?\/ ]{11})
///i
IMGUR_ID_REGEX = /https?:\/\/(?:i\.)?imgur\.com(?:\/a)?\/(.*?)(?:[\.#\/].*|$)/i
STREAMABLE_ID_REGEX = /https?:\/\/streamable\.com\/([a-zA-Z0-9]+)/i


class ThreadCtrl
  checkIfBanned: (groupId, ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByGroupIdAndIp groupId, ipAddr, {preferCache: true}
      Ban.getByGroupIdAndUserId groupId, userId, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId]) ->
      if bannedIp?.ip or bannedUserId?.userId
        router.throw status: 403, 'unable to post'

  getAttachment: (body) ->
    if youtubeId = body?.match(YOUTUBE_ID_REGEX)?[1]
      return Promise.resolve {
        type: 'video'
        src: "https://www.youtube.com/embed/#{youtubeId}?autoplay=1"
        previewSrc: "https://img.youtube.com/vi/#{youtubeId}/maxresdefault.jpg"
      }
    else if imgurId = body?.match(IMGUR_ID_REGEX)?[1]
      if body?.match /\.(gif|mp4|webm)/i
        return Promise.resolve {
          type: 'video'
          src: "https://i.imgur.com/#{imgurId}.mp4"
          previewSrc: "https://i.imgur.com/#{imgurId}h.jpg"
          mp4Src: "https://i.imgur.com/#{imgurId}.mp4"
          webmSrc: "https://i.imgur.com/#{imgurId}.webm"
        }
      else
        return Promise.resolve {
          type: 'image'
          src: "https://i.imgur.com/#{imgurId}.jpg"
        }
    else if streamableId = body?.match(STREAMABLE_ID_REGEX)?[1]
      return request "https://api.streamable.com/videos/#{streamableId}", {
        json: true
      }
      .then (data) ->
        paddingBottom = data.embed_code?.match(
          /padding-bottom: ([0-9]+\.?[0-9]*%)/i
        )?[1]
        aspectRatio = 100 / parseInt(paddingBottom)
        if isNaN aspectRatio
          aspectRatio = 1.777 # 16:9
        {
          type: 'video'
          src: "https://streamable.com/o/#{streamableId}"
          previewSrc: data.thumbnail_url
          aspectRatio: aspectRatio
        }

  upsert: ({thread, groupId, language}, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    thread.category ?= 'general'

    @checkIfBanned config.EMPTY_UUID, ip, user.id, router
    .then =>
      isProfane = ProfanityService.isProfane(
        thread.data.title + thread.data.body
      )
      msPlayed = Date.now() - user.joinTime?.getTime()

      if isProfane or user.flags.isChatBanned
        router.throw status: 400, info: 'unable to post...'

      if thread.data.body?.length > MAX_LENGTH
        router.throw status: 400, info: 'message is too long...'

      if not thread.data.body or not thread.data.title
        router.throw status: 400, info: 'can\'t be empty'

      if thread.data.title.match /like si\b/i
        router.throw status: 400, info: 'title must not contain that phrase'

      unless thread.id
        thread.category ?= 'general'

      images = new RegExp('\\!\\[(.*?)\\]\\((.*?)\\)', 'gi').exec(
        thread.data.body
      )
      firstImageSrc = images?[2]
      # for header image
      thread.data.attachments ?= []
      if _.isEmpty(thread.data.attachments) and firstImageSrc
        thread.data.attachments.push {
          type: 'image', src: firstImageSrc.replace(/^<|>$/g, '')
        }

      Promise.all [
        @getAttachment thread.data.body
        if thread.data.deck
          @addDeck thread.data.deck
        else
          Promise.resolve {}
      ]
      .then ([attachment, deckDiff]) =>
        if attachment
          thread.data.attachments.push attachment

        thread = _.defaultsDeep deckDiff, thread

        Group.getById groupId
        .then (group) =>
          @validateAndCheckPermissions thread, {user}
          .then (thread) ->
            if thread.id
              Thread.upsert thread
              .then ->
                deckKey = CacheService.PREFIXES.THREAD_DECK + ':' + thread.id
                key = CacheService.PREFIXES.THREAD + ':' + thread.id
                Promise.all [
                  CacheService.deleteByKey deckKey
                  CacheService.deleteByKey key
                ]
                {id: thread.id}
            else
              Thread.upsert _.defaults thread, {
                creatorId: user.id
                groupId: group?.id or config.GROUPS.CLASH_ROYALE_EN.ID
              }
      .tap ->
        # TODO: groupId
        CacheService.deleteByCategory CacheService.PREFIXES.THREADS_CATEGORY

  validateAndCheckPermissions: (thread, {user}) ->
    if thread.id
      threadPromise = Thread.getById thread.id
      hasPermission = threadPromise.then (existingThread) ->
        Thread.hasPermission existingThread, user, {
          level: 'member'
        }
    else
      hasPermission = Promise.resolve true

    Promise.all [
      threadPromise
      hasPermission
    ]
    .then ([existingThread, hasPermission]) ->
      thread = _.defaultsDeep thread, existingThread
      thread = _.pick thread, _.keys schemas.thread

      unless hasPermission
        router.throw status: 400, info: 'no permission'
      thread

  getAll: (options, {user}) ->
    {category, language, sort, maxTimeUuid, skip,
      limit, groupId} = options

    if category is 'all'
      category = null

    key = CacheService.PREFIXES.THREADS_CATEGORY + ':' + [
      groupId, category, language, sort, skip, maxTimeUuid, limit
    ].join(':')

    CacheService.preferCache key, ->
      Thread.getAll {
        category, sort, language, groupId, skip, maxTimeUuid, limit
      }
      .map (thread) ->
        EmbedService.embed {
          userId: user.id
          embed: if thread.data?.extras?.deckId \
                 then defaultEmbed.concat playerDeckEmbed
                 else defaultEmbed
        }, thread
      .map Thread.sanitize null
    , {
      expireSeconds: ONE_MINUTE_SECONDS
      category: CacheService.PREFIXES.THREADS_CATEGORY
    }
    .then (threads) ->
      if _.isEmpty threads
        return threads
      parents = _.map threads, ({id}) -> {type: 'thread', id}
      ThreadVote.getAllByCreatorIdAndParents user.id, parents
      .then (threadVotes) ->
        threads = _.map threads, (thread) ->
          thread.myVote = _.find threadVotes, ({parentId}) ->
            "#{parentId}" is "#{thread.id}"
          thread
        threads

  getById: ({id, language}, {user}) ->
    # legacy. rm in mid feb 2018
    if id is '7a39b079-e6ce-11e7-9642-4b5962cd09d3' # cr-es
      id = 'b3d49e6f-3193-417e-a584-beb082196a2c'
    else if id is '90c06cb0-86ce-4ed6-9257-f36633db59c2' # bruno
      id = 'fcb35890-f40e-11e7-9af5-920aa1303bef'

    key = CacheService.PREFIXES.THREAD + ':' + id

    CacheService.preferCache key, ->
      Thread.getById id
      .then EmbedService.embed {embed: defaultEmbed, userId: user.id}
      .then Thread.sanitize null
    , {expireSeconds: ONE_MINUTE_SECONDS}
    .then (thread) ->
      ThreadVote.getByCreatorIdAndParent user.id, {id, type: 'thread'}
      .then (myVote) ->
        thread.myVote = myVote
        thread

  deleteById: ({id}, {user}) ->
    Thread.getById id
    .then (thread) ->
      permission = GroupUser.PERMISSIONS.DELETE_FORUM_THREAD
      GroupUser.hasPermissionByGroupIdAndUser thread.groupId, user, [permission]
      .then (hasPermission) ->
        unless hasPermission
          router.throw
            status: 400, info: 'You don\'t have permission to do that'

        Thread.deleteById id
        .tap ->
          CacheService.deleteByCategory CacheService.PREFIXES.THREADS_CATEGORY

  pinById: ({id}, {user}) ->
    Thread.getById id
    .then (thread) ->
      permission = GroupUser.PERMISSIONS.PIN_FORUM_THREAD
      GroupUser.hasPermissionByGroupIdAndUser thread.groupId, user, [permission]
      .then (hasPermission) ->
        unless hasPermission
          router.throw
            status: 400, info: 'You don\'t have permission to do that'

        Thread.upsert {
          groupId: thread.groupId
          creatorId: thread.creatorId
          category: thread.category
          id: thread.id
          timeBucket: thread.timeBucket
          data: _.defaults {isPinned: true}, thread.data
        }
        .tap ->
          Thread.setPinnedThreadId id
          Promise.all [
            CacheService.deleteByCategory CacheService.PREFIXES.THREADS_CATEGORY
            CacheService.deleteByKey CacheService.PREFIXES.THREAD + ':' + id
          ]

  unpinById: ({id}, {user}) ->
    Thread.getById id
    .then (thread) ->
      permission = GroupUser.PERMISSIONS.PIN_FORUM_THREAD
      GroupUser.hasPermissionByGroupIdAndUser thread.groupId, user, [permission]
      .then (hasPermission) ->
        unless hasPermission
          router.throw
            status: 400, info: 'You don\'t have permission to do that'

        Thread.upsert {
          groupId: thread.groupId
          creatorId: thread.creatorId
          category: thread.category
          id: thread.id
          timeBucket: thread.timeBucket
          data: _.defaults {isPinned: false}, thread.data
        }
        .tap ->
          Thread.deletePinnedThreadId id
          Promise.all [
            CacheService.deleteByCategory CacheService.PREFIXES.THREADS_CATEGORY
            CacheService.deleteByKey CacheService.PREFIXES.THREAD + ':' + id
          ]

module.exports = new ThreadCtrl()
