_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'
basicAuth = require 'basic-auth'

ClashRoyaleAPIService = require '../services/clash_royale_api'
ClashRoyalePlayerService = require '../services/clash_royale_player'
ClashRoyaleAPIService = require '../services/clash_royale_api'
KueCreateService = require '../services/kue_create'
CacheService = require '../services/cache'
User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Player = require '../models/player'
PlayersDaily = require '../models/player_daily'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
UserRecord = require '../models/user_record'
Clan = require '../models/clan'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
config = require '../config'

defaultEmbed = []

PLAYER_MATCHES_TIMEOUT_MS = 10000
PLAYER_DATA_TIMEOUT_MS = 10000

WITH_ZACK_TAG = '89UC8VG'

class ClashRoyaleAPICtrl
  setByPlayerId: ({playerId, playerTag, isUpdate}, {user}) =>
    @refreshByPlayerId {
      playerId, playerTag, isUpdate, userId: user.id, priority: 'high'
    }, {user}
    .then ->
      if isUpdate
        Player.removeUserId user.id, config.CLASH_ROYALE_ID
    .then ->
      Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
      .then (player) ->
        if player?.id
          Player.updateByPlayerIdAndGameId player.id, config.CLASH_ROYALE_ID, {
            lastQueuedTime: new Date()
            updateFrequency: if player.updateFrequency is 'none' \
                             then 'default'
                             else player.updateFrequency
          }
        else
          Promise.all [
            ClashRoyaleUserDeck.duplicateByPlayerId playerTag, user.id
            .catch (err) ->
              console.log 'duplicate userdeck err', err
            UserRecord.duplicateByPlayerId playerTag, user.id
            .catch (err) ->
              console.log 'duplicate userrecord err', err
          ]

  refreshByPlayerId: ({playerTag, playerId, userId, priority}, {user}) ->
    playerId ?= playerTag # TODO: rm (legacy) June 2016
    playerId = playerId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidId = playerId.match /^[0289PYLQGRJCUV]+$/
    unless isValidId
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    Player.updateByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID, {
      lastQueuedTime: new Date()
    }
    ClashRoyaleAPIService.updatePlayerById playerId, {userId, priority}
    .catch ->
      router.throw {
        status: 400, info: 'unable to find that tag (typo?)'
        ignoreLog: true
      }
    .then ->
      return null

  updateByClanId: ({clanId}, {user}) ->
    Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID
    .then (clan) ->
      Clan.updateByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        lastQueuedTime: new Date()
      }
    .then ->
      ClashRoyaleAPIService.updateByClanId clanId

  # should only be called once daily
  updatePlayerData: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, playerData} = body
      unless tag
        return
      KueCreateService.createJob {
        job: {id: tag, playerData, isDaily: true}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA
        ttlMs: PLAYER_DATA_TIMEOUT_MS
        priority: 'low'
      }

  updateClan: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, clan} = body
      unless tag
        return
      KueCreateService.createJob {
        job: {tag, clan}
        type: KueCreateService.JOB_TYPES.UPDATE_CLAN_DATA
        priority: 'low'
      }

  updatePlayerMatches: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {matches} = body
      unless matches
        return
      KueCreateService.createJob {
        job: {matches, isBatched: true}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES
        ttlMs: PLAYER_MATCHES_TIMEOUT_MS
        priority: 'low'
      }

  queueClan: ({params}) ->
    console.log 'single queue clan', params.tag
    request "#{config.CR_API_URL}/clans/#{params.tag}", {
      json: true
      qs:
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updateClan"
    }

  queuePlayerData: ({params}) ->
    console.log 'single queue', params.tag, "#{config.CR_API_URL}/players/#{params.tag}"
    request "#{config.CR_API_URL}/players/#{params.tag}", {
      json: true
      qs:
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
    }

  queueTop200: ({params}) ->
    ClashRoyaleTopPlayer.getAll()
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      console.log playerIds.join(',')
      request "#{config.CR_API_URL}/players/#{playerIds.join(',')}", {
        json: true
        qs:
          callbackUrl:
            "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
      }

  queuePlayerMatches: ({params}) ->
    console.log 'single queue', params.tag
    request "#{config.CR_API_URL}/players/#{params.tag}/games", {
      json: true
      qs:
        callbackUrl:
          "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
    }

  updateTopPlayers: ->
    ClashRoyalePlayerService.updateTopPlayers()

  top200Decks: (req, res) ->
    credentials = basicAuth req
    {name, pass} = credentials or {}
    # insecure (pass is in here, but not a big deal for this)
    isAuthed = (name is 'sml' and pass is 'biob0t') or
               (name is 'woody' and pass is 'buzz')
    unless isAuthed
      res.setHeader 'WWW-Authenticate', 'Basic realm="radioactive"'
      console.log 'invalid admin'
      router.throw  {status: 401, info: 'Access denied'}

    ClashRoyaleTopPlayer.getAll()
    .map ({playerId}) ->
      Player.getByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID
    .then (players) ->
      decks = _.map players, (player) ->
        player?.data.currentDeck

      cards = _.flatten decks
      popularCards = _.countBy cards, 'key'
      popularCards = _.map popularCards, (usage, key) ->
        {key, usage}
      popularCards = _.orderBy popularCards, 'usage', 'desc'

      deckStrings = _.map decks, (deck) ->
        ClashRoyaleDeck.getDeckId _.map(deck, 'key')
      console.log deckStrings
      popularDecks = _.countBy deckStrings
      popularDecks = _.map popularDecks, (usage, key) ->
        {key, usage}
      popularDecks = _.filter popularDecks, ({usage}) -> usage > 1
      popularDecks = _.orderBy popularDecks, 'usage', 'desc'

      res.status(200).send {popularCards, popularDecks, decks}

  process: ->
    console.log '============='
    console.log 'process url called'
    console.log '============='
    # this triggers daily recap push notification
    # ClashRoyalePlayerService.updateStalePlayerData {force: true}
    ClashRoyalePlayerService.updateStalePlayerMatches {force: true}

module.exports = new ClashRoyaleAPICtrl()
