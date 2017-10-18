_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'
basicAuth = require 'basic-auth'

ClashRoyaleAPIService = require '../services/clash_royale_api'
ClashRoyalePlayerService = require '../services/clash_royale_player'
ClashRoyaleClanService = require '../services/clash_royale_clan'
ClashRoyaleAPIService = require '../services/clash_royale_api'
CacheService = require '../services/cache'
User = require '../models/user'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Player = require '../models/player'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
Clan = require '../models/clan'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
config = require '../config'

defaultEmbed = []

PLAYER_MATCHES_TIMEOUT_MS = 10000
PLAYER_DATA_TIMEOUT_MS = 10000

WITH_ZACK_TAG = '89UC8VG'
GAME_ID = config.CLASH_ROYALE_ID

class ClashRoyaleAPICtrl
  setByPlayerId: ({playerId, isUpdate}, {user}) =>
    (if isUpdate
      Player.removeUserId user.id, config.CLASH_ROYALE_ID
    else
      Promise.resolve null
    )
    .then ->
      Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
    .then (existingPlayer) =>
      @refreshByPlayerId {
        playerId, isUpdate, userId: user.id, priority: 'high'
      }, {user}
      .then ->
        if existingPlayer?.id
          Player.upsertByPlayerIdAndGameId existingPlayer.id, GAME_ID, {
            lastQueuedTime: new Date()
          }

  refreshByPlayerId: ({playerId, userId, isLegacy, priority}, {user}) ->
    playerId = ClashRoyaleAPIService.formatHashtag playerId

    isValidId = playerId and playerId.match /^[0289PYLQGRJCUV]+$/
    unless isValidId
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.REFRESH_PLAYER_ID_LOCK}:#{playerId}"
    # getting logs of multiple refreshes in same second - not sure why. this
    # should "fix". multiple at same time causes actions on matches
    # to be duplicated
    CacheService.lock key, ->
      console.log 'refresh', playerId
      Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
      .then (mePlayer) ->
        if mePlayer?.id is playerId
          userId = user.id
        Player.upsertByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID, {
          lastQueuedTime: new Date()
        }
        ClashRoyalePlayerService.updatePlayerById playerId, {
          userId, isLegacy, priority
        }
        .catch ->
          router.throw {
            status: 400, info: 'unable to find that tag (typo?)'
            ignoreLog: true
          }
      .then ->
        return null
    , {expireSeconds: 5, unlockWhenCompleted: true}

  refreshByClanId: ({clanId}, {user}) ->
    Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID
    .then (clan) ->
      Clan.upsertByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        lastQueuedTime: new Date()
      }
    .then ->
      ClashRoyaleClanService.updateClanById clanId

  # updatePlayerData: ({body, params, headers}) ->
  #   radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
  #   isPrivate = headers.host is radioactiveHost
  #   if isPrivate and body.secret is config.CR_API_SECRET
  #     {tag, playerData} = body
  #     unless tag
  #       return
  #     ClashRoyalePlayerService.updatePlayerData {id: tag, playerData}
  #
  # updateClan: ({body, params, headers}) ->
  #   radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
  #   isPrivate = headers.host is radioactiveHost
  #   if isPrivate and body.secret is config.CR_API_SECRET
  #     {tag, clan} = body
  #     unless tag
  #       return
  #     ClashRoyaleClanService.updateClan {tag, clan}
  #
  # updatePlayerMatches: ({body, params, headers}) ->
  #   radioactiveHost = config.RADIOACTIVE_API_URL.replace /https?:\/\//i, ''
  #   isPrivate = headers.host is radioactiveHost
  #   if isPrivate and body.secret is config.CR_API_SECRET
  #     {matches} = body
  #     unless matches
  #       return
  #     ClashRoyalePlayerService.filterMatches {matches, isBatched: true}
  #     .then (filteredMatches) ->
  #       # this doesn't set lastMatchTime for players...
  #       ClashRoyalePlayerService.updatePlayerMatches filteredMatches

  queueTop200: ({params}) ->
    ClashRoyaleTopPlayer.getAll()
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      console.log playerIds.join(',')
      request "#{config.CR_API_URL}/players/#{playerIds.join(',')}/games", {
        json: true
        qs:
          callbackUrl:
            "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
      }
      request "#{config.CR_API_URL}/players/#{playerIds.join(',')}", {
        json: true
        qs:
          callbackUrl:
            "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
      }

  updateTopPlayers: ->
    ClashRoyalePlayerService.updateTopPlayers()

  top200Decks: (req, res) ->
    credentials = basicAuth req
    {name, pass} = credentials or {}
    # insecure (pass is in here, but not a big deal for this)
    isAuthed = (name is 'sml' and pass is 'biob0t') or
               (name is 'seangar' and pass is 'grrrsean') or
               (name is 'woody' and pass is 'buzz')
    unless isAuthed
      res.setHeader 'WWW-Authenticate', 'Basic realm="radioactive"'
      console.log 'invalid admin'
      router.throw  {status: 401, info: 'Access denied'}

    useRecent = req.query?.useRecent

    ClashRoyaleTopPlayer.getAll()
    .map ({playerId}) ->
      Promise.all [
        if useRecent
          ClashRoyalePlayerDeck.getAllByPlayerId playerId, {
            limit: 1, sort: 'recent'
          }
        else
          Promise.resolve null
        Player.getByPlayerIdAndGameId playerId, config.CLASH_ROYALE_ID
      ]
    .then (players) ->
      decks = _.map players, ([playerDecks, player]) ->
        deckId = playerDecks?[0]?.deckId
        if deckId and deckId.indexOf('|') isnt -1
          playerDecks?[0]?.deckId?.split('|').map (key) -> {key}
        else
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

  updateAutoRefreshDebug: ->
    console.log '============='
    console.log 'process url called'
    console.log '============='
    ClashRoyalePlayerService.updateAutoRefreshPlayers()

module.exports = new ClashRoyaleAPICtrl()
