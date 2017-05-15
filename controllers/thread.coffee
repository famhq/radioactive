_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
uuid = require 'uuid'

User = require '../models/user'
UserData = require '../models/user_data'
Group = require '../models/group'
Thread = require '../models/thread'
ClashRoyaleDeck = require '../models/clash_royale_deck'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
ImageService = require '../services/image'
r = require '../services/rethinkdb'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.THREAD.CREATOR
  # EmbedService.TYPES.THREAD.COMMENT_COUNT
  EmbedService.TYPES.THREAD.SCORE
]
deckEmbed = [
  EmbedService.TYPES.THREAD.DECK
]

YOUTUBE_ID_REGEX = ///
  (?:youtube\.com\/(?:[^\/]+\/.+\/|(?:v|e(?:mbed)?)\/|.*[?&]v=)|youtu\.be\/)
  ([^"&?\/ ]{11})
///i

class ThreadCtrl
  createOrUpdateById: (diff, {user}) =>
    diff.data ?= {}
    (if diff.deck
      cardKeys = _.map diff.deck, 'key'
      cardIds = _.map diff.deck, 'id'
      name = ClashRoyaleDeck.getRandomName diff.deck
      ClashRoyaleDeck.getByCardKeys cardKeys
      .then (deck) ->
        if deck
          deck
        else
          ClashRoyaleDeck.create {
            cardIds, name, cardKeys, creatorId: user.id
          }
    else
      Promise.resolve null)
    .then (deck) =>
      if deck
        diff.data.deckId = deck.id
        diff.attachmentIds = [deck.id]
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
    .tap (deck) ->
      if deck.data?.videoUrl
        keyPrefix = "images/starfire/gv/#{deck.id}"
        youtubeId = deck.data.videoUrl.match(YOUTUBE_ID_REGEX)?[1]
        ImageService.getVideoPreview keyPrefix, youtubeId
        .then (videoPreview) ->
          if videoPreview
            Thread.updateById deck.id, {
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
    Thread.getById id
    .then (thread) ->
      hasVotedUp = thread.upvoteIds.indexOf(user.id) isnt -1
      hasVotedDown = thread.downvoteIds.indexOf(user.id) isnt -1
      if hasVotedUp and vote is 'up'
        router.throw status: 400, info: 'already voted'
      else if hasVotedDown and vote is 'down'
        router.throw status: 400, info: 'already voted'

      if vote is 'up'
        diff =
          upvotes: r.row('upvotes').add(1)
          upvoteIds: r.row('upvoteIds').append(user.id)
        if hasVotedDown
          diff.downvotes = r.row('downvotes').sub(1)
          diff.score = r.row('score').add(2)
          diff.downvoteIds = r.row('downvoteIds').difference([user.id])
        else
          diff.score = r.row('score').add(1)
      else if vote is 'down'
        diff =
          downvotes: r.row('downvotes').add(1)
          downvoteIds: r.row('downvoteIds').append(user.id)
        if hasVotedUp
          diff.upvotes = r.row('upvotes').sub(1)
          diff.score = r.row('score').sub(2)
          diff.upvoteIds = r.row('upvoteIds').difference([user.id])
        else
          diff.score = r.row('score').sub(1)

      Thread.updateById id, diff

  getAll: ({type}, {user}) ->
    Thread.getAll()
    .map EmbedService.embed {
      embed: if type is 'deckGuide' \
             then defaultEmbed.concat deckEmbed
             else defaultEmbed
    }
    .map Thread.sanitize null

  getById: ({id}, {user}) ->
    Thread.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then Thread.sanitize null

module.exports = new ThreadCtrl()
