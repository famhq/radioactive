_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
request = require 'request-promise'
uuid = require 'uuid'

User = require '../models/user'
UserData = require '../models/user_data'
Group = require '../models/group'
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
  checkIfBanned: (ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByIp ipAddr, {preferCache: true}
      Ban.getByUserId userId, {preferCache: true}
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

  createOrUpdateById: (diff, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    @checkIfBanned ip, user.id, router
    .then =>

      isProfane = ProfanityService.isProfane diff.title + diff.body
      msPlayed = Date.now() - user.joinTime?.getTime()

      if isProfane or user.flags.isChatBanned
        router.throw status: 400, info: 'unable to post...'

      if diff.body?.length > MAX_LENGTH
        router.throw status: 400, info: 'message is too long...'

      if not diff.body or not diff.title
        router.throw status: 400, info: 'can\'t be empty'

      unless diff.id
        diff.category ?= 'general'

      images = new RegExp('\\!\\[(.*?)\\]\\((.*?)\\)', 'gi').exec(diff.body)
      firstImageSrc = images?[2]
      # for header image
      diff.attachments ?= []
      if _.isEmpty(diff.attachments) and firstImageSrc
        diff.attachments.push [{type: 'image', src: firstImageSrc}]

      diff.data ?= {}
      Promise.all [
        @getAttachment diff.body
        if diff.deck
          @addDeck diff.deck
        else
          Promise.resolve {}
      ]
      .then ([attachment, deckDiff]) =>
        if attachment
          diff.attachments.push attachment

        diff = _.defaultsDeep deckDiff, diff

        @validateAndCheckPermissions diff, {user}
        .then (diff) ->
          if diff.id
            Thread.updateById diff.id, diff
            .then ->
              key = CacheService.PREFIXES.THREAD_DECK + ':' + diff.id
              CacheService.deleteByKey key
              {id: diff.id}
          else
            Thread.create _.defaults diff, {
              creatorId: user.id
            }
      .tap ->
        CacheService.deleteByCategory CacheService.PREFIXES.THREADS

  validateAndCheckPermissions: (diff, {user}) ->
    diff = _.pick diff, _.keys schemas.thread

    if diff.id
      hasPermission = Thread.hasPermissionByIdAndUser diff.id, user, {
        level: 'member'
      }
    else
      hasPermission = Promise.resolve true

    hasPermission
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'
      diff

  getAll: ({categories, language, sort, skip, limit, gameId}, {user}) ->
    gameId ?= config.CLASH_ROYALE_ID
    if not language in config.COMMUNITY_LANGUAGES and
        user.username isnt 'austin'
      categories ?= ['news']

    # default to this so clan recruiting isn't shown
    if not categories or categories[0] is 'all'
      categories = ['general', 'deckGuide']

    key = CacheService.PREFIXES.THREADS + ':' + [
      categories.join(','), language, sort, skip, limit
    ].join(':')

    CacheService.preferCache key, ->
      Promise.all [
        Thread.getAll {categories, sort, language, gameId, skip, limit}
        # mix in some new posts
        if sort is 'top' and not skip
          Thread.getAll {categories, sort: 'new', language, gameId, limit: 3}
        else
          Promise.resolve null
      ]
      .then ([allThreads, newThreads]) ->
        _.map newThreads, (thread, i) ->
          unless _.find allThreads, {id: thread.id}
            allThreads.splice (i + 1) * 2, 0, thread
        allThreads
      .map (thread) ->
        EmbedService.embed {
          userId: user.id
          embed: if thread.category is 'deckGuide' \
                 then defaultEmbed.concat playerDeckEmbed
                 else defaultEmbed
        }, thread
      .map (thread) ->
        if thread?.translations[language]
          _.defaults thread?.translations[language], thread
        else
          thread
      .map Thread.sanitize null
    , {
      expireSeconds: ONE_MINUTE_SECONDS
      category: CacheService.PREFIXES.THREADS
    }
    .then (threads) ->
      if _.isEmpty threads
        return threads
      parents = _.map threads, ({id}) -> {type: 'thread', id}
      ThreadVote.getAllByCreatorIdAndParents user.id, parents
      .then (threadVotes) ->
        threads = _.map threads, (thread) ->
          thread.myVote = _.find threadVotes, ({parentId}) ->
            "#{parentId}" is thread.id
          thread
        threads

  getById: ({id, language}, {user}) ->
    key = CacheService.PREFIXES.THREAD + ':' + id + ':' + language

    CacheService.preferCache key, ->
      Thread.getById id
      .then EmbedService.embed {embed: defaultEmbed, userId: user.id}
      .then (thread) ->
        if thread?.translations[language]
          _.defaults thread?.translations[language], thread
        else
          thread
      .then Thread.sanitize null
    , {expireSeconds: ONE_MINUTE_SECONDS}
    .then (thread) ->
      ThreadVote.getByCreatorIdAndParent user.id, {id, type: 'thread'}
      .then (myVote) ->
        thread.myVote = myVote
        thread

  deleteById: ({id}, {user}) ->
    unless user.flags.isModerator
      router.throw status: 400, info: 'no permission'
    Thread.deleteById id
    .tap ->
      CacheService.deleteByCategory CacheService.PREFIXES.THREADS

module.exports = new ThreadCtrl()
