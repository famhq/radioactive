_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'
basicAuth = require 'basic-auth'

ClashRoyalePlayerService = require '../services/clash_royale_player'
ClashRoyaleKueService = require '../services/clash_royale_kue'
KueCreateService = require '../services/kue_create'
CacheService = require '../services/cache'
User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Player = require '../models/player'
PlayersDaily = require '../models/player_daily'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
GameRecord = require '../models/game_record'
Clan = require '../models/clan'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
config = require '../config'

defaultEmbed = []

PLAYER_MATCHES_TIMEOUT_MS = 10000
PLAYER_DATA_TIMEOUT_MS = 10000

class ClashRoyaleAPICtrl
  refreshByPlayerTag: ({playerTag, isUpdate}, {user, headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress

    playerTag = playerTag.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = playerTag.match /^[0289PYLQGRJCUV]+$/
    console.log 'refresh', playerTag, ip
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag'}

    key = "#{CacheService.PREFIXES.CLASH_ROYALE_API_GET_TAG}:#{playerTag}"
    # TODO store kueJobId and use that instead of runOnce
    CacheService.runOnce key, ->
      (if isUpdate
        Player.removeUserId user.id, config.CLASH_ROYALE_ID
      else
        Promise.resolve null)
      .then ->
        Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
      .then (player) ->
        if player?.id
          Player.updateById player.id, {
            lastQueuedTime: new Date()
            # if lastQueuedTime in last 10 min, and kueJobId, sub to that?
            # TODO: kueJobId: ...
          }
        else
          Promise.all [
            ClashRoyaleUserDeck.duplicateByPlayerId playerTag, user.id
            GameRecord.duplicateByPlayerId playerTag, user.id
          ]
      .then ->
        ClashRoyaleKueService.refreshByPlayerTag playerTag, {userId: user.id}
      .then ->
        console.log 'refresh done'
        return null
    , {
      expireSeconds: 60
      lockedFn: ->
        router.throw {status: 400, info: 'we\'re already processing that tag'}
    }

  refreshByClanId: ({clanId}, {user}) ->
    Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID
    .then (clan) ->
      Clan.updateById clan.id, {
        lastQueuedTime: new Date()
      }
    .then ->
      ClashRoyaleKueService.refreshByClanId clanId

  # should only be called once daily
  updatePlayerData: ({body, params, headers}) ->
    radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
    isPrivate = headers.host is radioactiveHost
    if isPrivate and body.secret is config.CR_API_SECRET
      {tag, playerData} = body
      unless tag
        return
      KueCreateService.createJob {
        job: {tag, playerData, isDaily: true}
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
    console.log 'single queue', params.tag
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
