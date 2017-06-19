_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
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
  EmbedService.TYPES.THREAD.SCORE
  EmbedService.TYPES.THREAD.MY_VOTE
]
deckEmbed = [
  EmbedService.TYPES.THREAD.DECK
]

MAX_LENGTH = 5000
YOUTUBE_ID_REGEX = ///
  (?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)
  ([^"&?\/ ]{11})
///i

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

  addDeck: (deck) ->
    cardKeys = _.map deck, 'key'
    cardIds = _.map deck, 'id'
    name = ClashRoyaleDeck.getRandomName deck
    ClashRoyaleDeck.getByCardKeys cardKeys
    .then (deck) ->
      if deck
        deck
      else
        ClashRoyaleDeck.create {
          cardIds, name, cardKeys, creatorId: user.id
        }
    .then (deck) ->
      if deck
        {
          data:
            deckId: deck.id
          attachmentIds: [deck.id]
        }
      else
        {}


  createOrUpdateById: (diff, {user, headers, connection}) =>
    userAgent = headers['user-agent']
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    isProfane = ProfanityService.isProfane diff.title + diff.body
    msPlayed = Date.now() - user.joinTime?.getTime()

    if isProfane or user.flags.isChatBanned
      router.throw status: 400, info: 'unable to post...'

    if diff.body?.length > MAX_LENGTH
      router.throw status: 400, info: 'message is too long...'

    if not diff.body or not diff.title
      router.throw status: 400, info: 'can\'t be empty'

    diff.data ?= {}
    (if diff.deck
      @addDeck diff.deck
    else
      Promise.resolve {}
    )
    .then (deckDiff) =>
      diff = _.defaultsDeep deckDiff, diff
      if diff.data.videoUrl
        youtubeId = diff.data.videoUrl.match(YOUTUBE_ID_REGEX)?[1]
        diff.data.videoUrl =
          "https://www.youtube.com/embed/#{youtubeId}?autoplay=1"

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
    .tap (thread) ->
      if thread.data?.videoUrl
        keyPrefix = "images/starfire/gv/#{thread.id}"
        youtubeId = thread.data.videoUrl.match(YOUTUBE_ID_REGEX)?[1]
        ImageService.getVideoPreview keyPrefix, youtubeId
        .then (videoPreview) ->
          if videoPreview
            Thread.updateById thread.id, {
              headerImage: videoPreview
            }

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

  voteById: ({id, vote}, {user}) ->
    Promise.all [
      Thread.getById id
      ThreadVote.getByCreatorIdAndParent user.id, id, 'thread'
    ]
    .then ([thread, existingVote]) ->
      voteNumber = if vote is 'up' then 1 else -1

      hasVotedUp = existingVote?.vote is 1
      hasVotedDown = existingVote?.vote is -1
      if existingVote and voteNumber is existingVote.vote
        router.throw status: 400, info: 'already voted'

      if vote is 'up'
        diff = {upvotes: r.row('upvotes').add(1)}
        if hasVotedDown
          diff.downvotes = r.row('downvotes').sub(1)
      else if vote is 'down'
        diff = {downvotes: r.row('downvotes').add(1)}
        if hasVotedUp
          diff.upvotes = r.row('upvotes').sub(1)

      Promise.all [
        if existingVote
          ThreadVote.updateById existingVote.id, {vote: voteNumber}
        else
          ThreadVote.create {
            creatorId: user.id
            parentId: id
            parentType: 'thread'
            vote: voteNumber
          }

        Thread.updateById id, diff
      ]

  getAll: ({category, language, sort, limit}, {user}) ->
    if language is 'es'
      category = ''
    else
      category ?= 'news'

    Thread.getAll {category, sort, limit}
    .map EmbedService.embed {
      userId: user.id
      embed: if category is 'decks' \
             then defaultEmbed.concat deckEmbed
             else defaultEmbed
    }
    .map (thread) ->
      if thread?.translations[language]
        _.defaults thread?.translations[language], thread
      else
        thread
    .map Thread.sanitize null

  getById: ({id, language}, {user}) ->
    Thread.getById id
    .then EmbedService.embed {embed: defaultEmbed, userId: user.id}
    .then (thread) ->
      if thread?.translations[language]
        _.defaults thread?.translations[language], thread
      else
        thread
    .then Thread.sanitize null

module.exports = new ThreadCtrl()
