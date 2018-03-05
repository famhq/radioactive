_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
router = require 'exoid-router'
basicAuth = require 'basic-auth'

ClashRoyaleService = require '../services/game_clash_royale'
ClashRoyaleClanService = require '../services/clash_royale_clan'
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
GAME_KEY = 'clash-royale'

class ClashRoyaleAPICtrl
  refreshByClanId: ({clanId}, {user}) ->
    Clan.getByClanIdAndGameKey clanId, GAME_KEY
    .then (clan) ->
      Clan.upsertByClanIdAndGameKey clanId, GAME_KEY, {
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
  #     ClashRoyaleService.updatePlayerData {id: tag, playerData}
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
  #     ClashRoyaleService.filterMatches {matches, isBatched: true}
  #     .then (filteredMatches) ->
  #       # this doesn't set lastMatchTime for players...
  #       ClashRoyaleService.updatePlayerMatches filteredMatches

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
    ClashRoyaleService.updateTopPlayers()

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
        Player.getByPlayerIdAndGameKey playerId, GAME_KEY
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
    ClashRoyaleService.updateAutoRefreshPlayers()

module.exports = new ClashRoyaleAPICtrl()
