Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

KueCreateService = require './kue_create'
TagConverterService = require './tag_converter'
CacheService = require './cache'
Clan = require '../models/clan'
config = require '../config'

API_REQUEST_TIMEOUT_MS = 10000
ONE_DAY_SECONDS = 3600 * 24

class ClashRoyaleAPIService
  formatHashtag: (hashtag) ->
    unless hashtag
      return null
    return hashtag.trim().toUpperCase()
            .replace '#', ''
            .replace /O/g, '0' # replace capital O with zero

  isValidTag: (hashtag) ->
    hashtag.match /^[0289PYLQGRJCUV]+$/

  isInvalidTagInCache: (type, tag) ->
    unless type or tag
      return Promise.resolve false
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.get key

  setInvalidTag: (type, tag) ->
    unless type or tag
      return
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.set key, true, {expireSeconds: ONE_DAY_SECONDS}

  request: (path, {tag, type, method, body, qs, priority} = {}) ->
    method ?= 'GET'

    KueCreateService.createJob {
      job: {path, tag, type, method, body, qs}
      type: KueCreateService.JOB_TYPES.API_REQUEST
      ttlMs: API_REQUEST_TIMEOUT_MS
      priority: priority
      waitForCompletion: true
    }

  processRequest: ({path, tag, type, method, body, qs}) =>
    # start = Date.now()
    request "#{config.CLASH_ROYALE_API_URL}#{path}", {
      json: true
      method: method
      headers:
        'Authorization': "Bearer #{config.CLASH_ROYALE_API_KEY}"
      body: body
    }
    .then (response) ->
      # console.log 'realAPIreq', Date.now() - start
      response
    .catch (err) =>
      if err.statusCode is 404
        @setInvalidTag type, tag
        .then ->
          throw err
      else
        throw err

  getPlayerDataByTag: (tag, {priority, skipCache, isLegacy} = {}) =>
    tag = @formatHashtag tag

    unless @isValidTag tag
      throw new Error 'invalid tag'

    if not isLegacy
      Promise.all [
        @request "/players/%23#{tag}", {type: 'player', tag, priority}
        @request "/players/%23#{tag}/upcomingchests", {type: 'player', tag}
      ]
      .then ([player, upcomingChests]) ->
        player.upcomingChests = upcomingChests
        player
    else # verifying with gold or getting shop offers
      request "#{config.CR_API_URL}/players/#{tag}", {
        json: true
        qs:
          priority: priority
          skipCache: skipCache
      }
      .then (responses) ->
        responses?[0]

  getPlayerMatchesByTag: (tag, {priority} = {}) =>
    tag = @formatHashtag tag

    unless @isValidTag tag
      throw new Error 'invalid tag'

    @request "/players/%23#{tag}/battlelog", {type: 'player', tag, priority}
    .then (matches) ->
      if _.isEmpty matches
        throw new Error '404' # api should do this, but just does empty arr
      _.map matches, (match) ->
        match.id = "#{match.battleTime}:" +
                    "#{match.team[0].tag}:#{match.opponent[0].tag}"
        match.battleTime = moment(match.battleTime).toDate()
        match.battleType = if match.challengeId is 65000000 \
                     then 'grandChallenge'
                     else if match.challengeId is 65000001
                     then 'classicChallenge'
                     else if match.challengeId is 73001201
                     then 'touchdown2v2DraftPractice'
                     else if match.challengeId is 73001203
                     then 'touchdown2v2Draft'
                     else match.type
        match

  getClanByTag: (tag, {priority} = {}) =>
    tag = @formatHashtag tag

    unless @isValidTag tag
      throw new Error 'invalid tag'

    @request "/clans/%23#{tag}", {type: 'clan', tag}
    .catch (err) ->
      console.log 'err clanByTag', err

  getTopPlayers: (locationId) =>
    @request '/locations/global/rankings/players'

module.exports = new ClashRoyaleAPIService()
