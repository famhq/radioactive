Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

KueCreateService = require './kue_create'
TagConverterService = require './tag_converter'
CacheService = require './cache'
Clan = require '../models/clan'
config = require '../config'

PLAYER_DATA_TIMEOUT_MS = 10000
PLAYER_MATCHES_TIMEOUT_MS = 10000
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
      return false
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.get key

  setInvalidTag: (type, tag) ->
    unless type or tag
      return
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.set key, true, {expireSeconds: ONE_DAY_SECONDS}

  request: (path, {tag, type, method, body, qs} = {}) =>
    method ?= 'GET'

    @isInvalidTagInCache type, tag
    .then (isInvalid) =>
      if isInvalid
        throw new Error 'invalid tag'

      request "#{config.CLASH_ROYALE_API_URL}#{path}", {
        json: true
        method: method
        headers:
          'Authorization': "Bearer #{config.CLASH_ROYALE_API_KEY}"
        body: body
      }
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
      console.log 'invalid'
      throw new Error 'invalid tag'

    useNew = Math.random() < 1.1

    if useNew and not isLegacy
      @request "/players/%23#{tag}", {type: 'player', tag}
      .then (player) =>
        @request "/players/%23#{tag}/upcomingchests", {type: 'player', tag}
        .then (upcomingChests) ->
          player.upcomingChests = upcomingChests
          player
    else # verifying with gold
      console.log "#{config.CR_API_URL}/players/#{tag}"
      request "#{config.CR_API_URL}/players/#{tag}", {
        json: true
        qs:
          priority: priority
          skipCache: skipCache
      }
      .then (responses) ->
        responses?[0]

  getPlayerMatchesByTag: (tag, {priority} = {}) =>
    useNew = Math.random() < 1.1

    tag = @formatHashtag tag

    unless @isValidTag tag
      throw new Error 'invalid tag'

    if useNew
      @request "/players/%23#{tag}/battlelog", {type: 'player', tag}
      .then (matches) ->
        _.map matches, (match) ->
          match.id = "#{match.battleTime}:" +
                      "#{match.team[0].tag}:#{match.opponent[0].tag}"
          match.battleType = if match.challengeTitle is 'Grand Challenge' \
                       then 'grandChallenge'
                       else if match.type is 'challenge'
                       then 'classicChallenge'
                       else match.type
          match
    else
      request "#{config.CR_API_URL}/players/#{tag}/games", {
        json: true
        qs:
          priority: priority
      }
      .then (responses) ->
        _.map responses?[0], (match) ->
          # match = _.cloneDeep match
          match.id = "#{match.battleTime}:" +
                      "#{match.team[0].tag}:#{match.opponent[0].tag}"
          match.battleType = if match.challengeTitle is 'Grand Challenge' \
                       then 'grandChallenge'
                       else if match.type is 'challenge'
                       then 'classicChallenge'
                       else match.type
          match
      .catch (err) ->
        console.log 'err playerMatchesByTag', err

  updatePlayerById: (playerId, {userId, priority} = {}) =>
    Promise.all [
      @getPlayerDataByTag playerId, {priority}
      @getPlayerMatchesByTag playerId, {priority}
      .catch -> null
    ]
    .then ([playerData, matches]) ->
      unless playerId and playerData
        console.log 'update missing tag or data', playerId, playerData
        throw new Error 'unable to find that tag'
      unless matches
        console.log 'matches error', playerId
      KueCreateService.createJob {
        job: {userId: userId, id: playerId, playerData}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA
        ttlMs: PLAYER_DATA_TIMEOUT_MS
        priority: priority or 'high'
        waitForCompletion: true
      }
      .then ->
        KueCreateService.createJob {
          job: {tag: playerId, matches}
          type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES
          ttlMs: PLAYER_MATCHES_TIMEOUT_MS
          priority: priority or 'high'
          waitForCompletion: true
        }
        .timeout PLAYER_MATCHES_TIMEOUT_MS
        .catch -> null

  getClanByTag: (tag, {priority} = {}) =>
    useNew = Math.random() < 1.1

    tag = @formatHashtag tag

    unless @isValidTag tag
      throw new Error 'invalid tag'

    if useNew
      @request "/clans/%23#{tag}", {type: 'clan', tag}
      .catch (err) ->
        console.log 'err clanByTag', err
    else
      request "#{config.CR_API_URL}/clans/#{tag}", {
        json: true
        qs:
          priority: priority
      }
      .then (responses) ->
        responses?[0]
      .catch (err) ->
        console.log 'err clanByTag', err

  updateByClanId: (clanId, {userId, priority} = {}) =>
    @getClanByTag clanId, {priority}
    .then (clan) ->
      KueCreateService.createJob {
        job: {userId: userId, tag: clanId, clan}
        type: KueCreateService.JOB_TYPES.UPDATE_CLAN_DATA
        priority: priority or 'high'
        waitForCompletion: true
      }
    .then ->
      Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        preferCache: true
      }
      .then (clan) ->
        if clan
          {id: clan?.id}

module.exports = new ClashRoyaleAPIService()
