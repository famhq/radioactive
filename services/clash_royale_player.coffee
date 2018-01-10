Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

Player = require '../models/player'
Clan = require '../models/clan'
Language = require '../models/language'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
ClashRoyalePlayer = require '../models/clash_royale_player'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
ClashRoyaleClanService = require './clash_royale_clan'
CacheService = require './cache'
KueCreateService = require './kue_create'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
PushNotificationService = require './push_notification'
ClashRoyaleAPIService = require './clash_royale_api'
EmbedService = require './embed'
Match = require '../models/clash_royale_match'
User = require '../models/user'
config = require '../config'

# for now we're not storing user deck info of players that aren't on starfire.
# should re-enable if we can handle the added load from it.
# big issue is 2v2
ENABLE_ANON_PLAYER_DECKS = false

AUTO_REFRESH_PLAYER_TIMEOUT_MS = 30 * 1000
ONE_MINUTE_SECONDS = 60
ONE_DAY_S = 3600 * 24
SIX_HOURS_S = 3600 * 6
ONE_DAY_MS = 3600 * 24 * 1000
CLAN_TIMEOUT_MS = 5000
GAME_ID = config.CLASH_ROYALE_ID

ALLOWED_GAME_TYPES = [
  'PvP', 'tournament',
  'classicChallenge', 'grandChallenge'
  'friendly', 'clanMate', '2v2', 'touchdown2v2DraftPractice',
  'touchdown2v2Draft', 'newCardChallenge', '3xChallenge', 'rampUp'
]

DEBUG = false or config.ENV is config.ENVS.DEV
IS_TEST_RUN = false and config.ENV is config.ENVS.DEV

class ClashRoyalePlayerService
  filterMatches: ({matches, tag, isBatched}) =>
    tags = if isBatched then _.map matches, 'tag' else [tag]

    # get before update so we have accurate lastMatchTime
    Player.getAllByPlayerIdsAndGameId tags, GAME_ID
    .then (players) =>
      if isBatched
        Promise.map(players, (player) =>
          chunkMatches = _.find(matches, {tag: player.id})?.matches
          @filterMatchesByPlayer {matches: chunkMatches, player}
        ).then _.flatten
      else
        @filterMatchesByPlayer {matches, player: players[0]}

  filterMatchesByPlayer: ({matches, player}) ->
    # only grab matches since the last update time
    matches = _.filter matches, (match) ->
      unless match
        return false
      {battleTime, battleType} = match

      if player?.data?.lastMatchTime
        lastMatchTime = new Date player.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      (battleType in ALLOWED_GAME_TYPES) and
        (
          IS_TEST_RUN
          battleTime.getTime() >
            (new Date(lastMatchTime).getTime() + 15)
        )

    Promise.map matches, (match) ->
      playerId = match.team[0].tag.replace '#', ''
      Match.existsByPlayerIdAndTime playerId, match.battleTime, {
        preferCache: true
      }
      .then (existingMatch) ->
        if existingMatch and not IS_TEST_RUN then null else match
    .then _.filter

  processMatches: ({matches}) ->
    if _.isEmpty matches
      return Promise.resolve null
    matches = _.uniqBy matches, 'id'
    # matches = _.orderBy matches, ['battleTime'], ['asc']

    if DEBUG
      console.log 'filtered matches: ' + matches.length

    formattedMatches = _.map matches, (match, i) ->
      matchId = match.id

      team = match.team
      teamDeckIds = _.map team, (player) ->
        cardKeys = _.map player.cards, ({name}) ->
          ClashRoyaleCard.getKeyByName name
        ClashRoyaleDeck.getDeckId cardKeys
      teamCardIds = _.flatten _.map team, (player) ->
        _.map player.cards, ({name}) ->
          ClashRoyaleCard.getKeyByName name

      opponent = match.opponent
      opponentDeckIds = _.map opponent, (player) ->
        cardKeys = _.map player.cards, ({name}) ->
          ClashRoyaleCard.getKeyByName name
        ClashRoyaleDeck.getDeckId cardKeys
      opponentCardIds = _.flatten _.map opponent, (player) ->
        _.map player.cards, ({name}) ->
          ClashRoyaleCard.getKeyByName name

      type = match.battleType

      teamWon = match.team[0].crowns > match.opponent[0].crowns
      opponentWon = match.opponent[0].crowns > match.team[0].crowns

      if teamWon
        winningDeckIds = teamDeckIds
        losingDeckIds = opponentDeckIds
        drawDeckIds = null
        winningDeckCardIds = teamCardIds
        losingDeckCardIds = opponentCardIds
        drawDeckCardIds = null
        winningCrowns = match.team[0].crowns
        losingCrowns = match.opponent[0].crowns
        winners = team
        losers = opponent
        draws = null
      else if opponentWon
        winningDeckIds = opponentDeckIds
        losingDeckIds = teamDeckIds
        drawDeckIds = null
        winningDeckCardIds = opponentCardIds
        losingDeckCardIds = teamCardIds
        drawDeckCardIds = null
        winningCrowns = match.opponent[0].crowns
        losingCrowns = match.team[0].crowns
        winners = opponent
        losers = team
        draws = null
      else
        winningDeckIds = null
        losingDeckIds = null
        drawDeckIds = teamDeckIds.concat opponentDeckIds
        winningDeckCardIds = null
        losingDeckCardIds = null
        drawDeckCardIds = teamCardIds.concat opponentCardIds
        winningCrowns = match.team[0].crowns
        losingCrowns = match.opponent[0].crowns
        winners = null
        losers = null
        draws = team.concat opponent

      winningPlayerIds = _.map winners, (player) ->
        ClashRoyaleAPIService.formatHashtag player.tag
      losingPlayerIds = _.map losers, (player) ->
        ClashRoyaleAPIService.formatHashtag player.tag
      drawPlayerIds = _.map draws, (player) ->
        ClashRoyaleAPIService.formatHashtag player.tag

      prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID_EXISTS
      key = "#{prefix}:#{matchId}"

      # uses less cpu than a map and omit
      _.forEach match.team, (player, i) ->
        _.forEach player.cards, (card, j) ->
          delete match.team[i].cards[j].iconUrls
      _.forEach match.opponent, (player, i) ->
        _.forEach player.cards, (card, j) ->
          delete match.opponent[i].cards[j].iconUrls

      # don't need to block for this
      CacheService.set key, true, {expireSeconds: SIX_HOURS_S}

      matchMomentTime = moment(match.battleTime)

      {
        id: matchId
        data: match
        arena: match.arena?.id
        type: type
        winningPlayerIds: winningPlayerIds
        losingPlayerIds: losingPlayerIds
        drawPlayerIds: drawPlayerIds
        winningDeckIds: winningDeckIds
        losingDeckIds: losingDeckIds
        drawDeckIds: drawDeckIds
        winningCardIds: winningDeckCardIds
        losingCardIds: losingDeckCardIds
        drawCardIds: drawDeckCardIds
        winningCrowns: winningCrowns
        losingCrowns: losingCrowns
        time: match.battleTime
        momentTime: matchMomentTime
      }

    start = Date.now()

    try
      Promise.all [
        ClashRoyalePlayer.batchUpsertCounterByMatches formattedMatches
        .catch (err) -> console.log 'player err', err
        .then -> if DEBUG then console.log '---player', Date.now() - start

        Match.batchCreate formattedMatches
        .catch (err) -> console.log 'match err', err
        .then -> if DEBUG then console.log '---match', Date.now() - start

        ClashRoyalePlayerRecord.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'playerrecord err', err
        .then -> if DEBUG then console.log '---gr', Date.now() - start

        ClashRoyalePlayerDeck.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'playerDeck err', err
        .then -> if DEBUG then console.log '---pdeck', Date.now() - start

        ClashRoyaleDeck.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'decks err', err
        .then -> if DEBUG then console.log '---deck', Date.now() - start

        ClashRoyaleCard.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'cards err', err
        .then -> if DEBUG then console.log '---card', Date.now() - start
      ]
      .then ->
        formattedMatches
      .catch (err) -> console.log err
    catch err
      console.log err

  updatePlayerMatches: ({matches, tag}) =>
    if _.isEmpty matches
      Player.upsertByPlayerIdAndGameId tag, GAME_ID, {
        lastUpdateTime: new Date()
      }

    @processMatches {matches}
    .tap (matches) ->
      if tag
        Player.getByPlayerIdAndGameId tag, GAME_ID

  updatePlayerById: (playerId, options = {}) =>
    {userId, isLegacy, priority, isAuto} = options
    start = Date.now()
    ClashRoyaleAPIService.isInvalidTagInCache 'player', playerId
    .then (isInvalid) =>
      if isInvalid
        throw new Error 'invalid tag'
      ClashRoyaleAPIService.getPlayerMatchesByTag playerId, {
        priority
        skipThrow: not isAuto # don't throw 404 if matches are empty
      }
      .then (matches) =>
        if DEBUG
          console.log 'all', matches.length
        @filterMatches {matches, tag: playerId}
      .then (matches) =>
        if DEBUG
          console.log 'filtered', matches.length
        (if not isAuto or not _.isEmpty matches
          ClashRoyaleAPIService.getPlayerDataByTag playerId, {
            priority, isLegacy
          }
        else
          Promise.resolve null)
        .then (playerData) =>
          if DEBUG
            console.log 'api requests', Date.now() - start

          Promise.all _.filter [
            if playerData
              @updatePlayerData {
                id: playerId, lastMatchTime: _.first(matches)?.time
                playerData, userId, isAuto
              }

            @updatePlayerMatches {tag: playerId, matches}
          ]

      .catch (err) ->
        console.log 'caught updatePlayerId', err
        throw err
    .then ->
      true # notify auto_refresher of success

  updatePlayerData: ({userId, playerData, id, lastMatchTime, isAuto}) =>
    if DEBUG
      console.log 'update player data', id
    unless id and playerData
      return Promise.resolve null

    clanId = playerData?.clan?.tag?.replace '#', ''

    Player.getByPlayerIdAndGameId id, GAME_ID
    .then (existingPlayer) =>
      # bug fix for merging legacy api chest cycle and new API
      if existingPlayer?.data?.upcomingChests and playerData?.upcomingChests
        delete existingPlayer.data.upcomingChests
      diff = {
        data: _.defaultsDeep(
          playerData
          # @getPlayerFromPlayerData({playerData})
          existingPlayer?.data or {}
        )
        lastUpdateTime: new Date()
      }
      if lastMatchTime
        diff.data.lastMatchTime = lastMatchTime

      # NOTE: any time you update, keep in mind scylla replaces
      # entire fields (data), so need to merge with old data manually
      Player.upsertByPlayerIdAndGameId id, GAME_ID, diff, {userId}
      .then =>
        if clanId and userId
          @_setClan {clanId, userId}
      .catch (err) ->
        console.log 'upsert err', err
        null

      .tap =>
        key = CacheService.PREFIXES.USER_DAILY_DATA_PUSH + ':' + id
        CacheService.runOnce key, =>
          @sendDailyPush {playerId: id, isAuto}
          .catch (err) ->
            console.log 'push err', err
        , {expireSeconds: ONE_DAY_S}
        null # don't need to block

  _setClan: ({clanId, userId}) ->
    Clan.getByClanIdAndGameId clanId, GAME_ID, {
      preferCache: true
    }
    .then (clan) ->
      if not clan?.data and clanId
        ClashRoyaleClanService.updateClanById clanId, {userId}
        .timeout CLAN_TIMEOUT_MS
        .catch (err) ->
          console.log 'clan refresh err', err
          null

  updateAutoRefreshPlayers: =>
    start = Date.now()
    CacheService.lock CacheService.LOCKS.AUTO_REFRESH, ->
      key = CacheService.KEYS.AUTO_REFRESH_MAX_REVERSED_PLAYER_ID
      CacheService.get key
      .then (minReversedPlayerId) ->
        minReversedPlayerId ?= '0'
        # TODO: add a check to make sure this is always running. healtcheck?
        Player.getAutoRefreshByGameId GAME_ID, minReversedPlayerId
        .then (players) ->
          console.log 'auto refreshing', minReversedPlayerId, players.length
          if _.isEmpty players
            buckets = '0289PYLQGRJCUV'.split ''
            currentBucket = minReversedPlayerId.substr 0, 1
            currentBucketIndex = buckets.indexOf currentBucket
            newBucketIndex = (currentBucketIndex + 1) % buckets.length
            newBucket = buckets[newBucketIndex]
            newMinReversedPlayerId = newBucket
          else
            newMinReversedPlayerId = _.last(players).reversedPlayerId

          CacheService.set key, newMinReversedPlayerId, {
            expireSeconds: ONE_MINUTE_SECONDS
          }
          # add each player to kue
          # once all processed, call update again with new minPlayerId
          Promise.map players, ({playerId}) ->
            KueCreateService.createJob {
              job: {playerId}
              type: KueCreateService.JOB_TYPES.AUTO_REFRESH_PLAYER
              ttlMs: AUTO_REFRESH_PLAYER_TIMEOUT_MS
              priority: 'high'
              waitForCompletion: true
            }
            .catch (err) ->
              console.log 'caught', playerId, err
    , {expireSeconds: 120, unlockWhenCompleted: true}
    .then (responses) =>
      isLocked = not responses
      if isLocked
        console.log 'skip (locked)'
      else
        # always be truthy for cron-check
        successes = _.filter(responses).length or 1
        console.log 'refreshing success', successes, 'time', Date.now() - start
        key = CacheService.KEYS.AUTO_REFRESH_SUCCESS_COUNT
        CacheService.set key, successes, {expireSeconds: ONE_MINUTE_SECONDS}
        # TODO: make sure this doesn't cause memory leak.
        # i think the null prevents it
        @updateAutoRefreshPlayers()
      null

  sendDailyPush: ({playerId, isAuto}) ->
    yesterday = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
      'day'
      moment().subtract 1, 'day'
    )
    console.log 'sending daily push', playerId, isAuto, GAME_ID
    Promise.all [
      Player.getByPlayerIdAndGameId playerId, GAME_ID
      .then EmbedService.embed {
        embed: [
          EmbedService.TYPES.PLAYER.USER_IDS
        ]
        gameId: GAME_ID
      }
      Player.getCountersByPlayerIdAndScaledTimeAndGameId(
        playerId, yesterday, GAME_ID
      )
    ]
    .then ([player, playerCounters]) ->
      if player
        goodChests = ['giantChest', 'epicChest', 'legendaryChest',
                      'superMagicalChest', 'magicalChest']
        goodChests = _.map goodChests, (chest) ->
          _.find player.data.upcomingChests?.items, {name: _.startCase(chest)}
        nextGoodChest = _.minBy goodChests, 'index'
        unless nextGoodChest
          return
        countUntilNextGoodChest = nextGoodChest.index + 1

        playerCounter = _.find playerCounters, {gameType: 'all'}

        unless _.isEmpty player.userIds
          Promise.map player.userIds, (userId) ->
            User.getById userId, {preferCache: true}
          .map (user) ->
            PushNotificationService.send user, {
              titleObj:
                key: 'dailyRecap.title'
              textObj:
                key: if playerCounter \
                     then 'dailyRecap.textWithWins'
                     else 'dailyRecap.text'
                replacements:
                  countUntilNextGoodChest: countUntilNextGoodChest
                  nextGoodChest: _.startCase nextGoodChest?.name
                  wins: playerCounter?.wins
                  losses: playerCounter?.losses
              type: PushNotificationService.TYPES.DAILY_RECAP
              data:
                path:
                  key: 'home'
                  params:
                    gameKey: config.DEFAULT_GAME_KEY
            }
        null

  getTopPlayers: ->
    ClashRoyaleAPIService.getTopPlayers()

  updateTopPlayers: =>
    @getTopPlayers().then (response) =>
      topPlayers = response?.items
      Promise.map topPlayers, (player, index) =>
        rank = index + 1
        playerId = ClashRoyaleAPIService.formatHashtag player.tag
        Player.getByPlayerIdAndGameId playerId, GAME_ID
        .then EmbedService.embed {
          embed: [EmbedService.TYPES.PLAYER.USER_IDS]
          gameId: GAME_ID
        }
        .then (existingPlayer) =>
          if existingPlayer?.data and not _.isEmpty existingPlayer?.userIds
            newPlayer = _.defaultsDeep {
              data:
                trophies: player.trophies
                name: player.name
            }, existingPlayer
            # NOTE: any time you update, keep in mind postgress replaces
            # entire fields (data), so need to merge with old data manually
            Player.upsertByPlayerIdAndGameId playerId, GAME_ID, newPlayer
          else
            @updatePlayerById playerId, {
              priority: 'normal'
            }

        .then ->
          ClashRoyaleTopPlayer.upsertByRank rank, {
            playerId: playerId
          }

module.exports = new ClashRoyalePlayerService()
