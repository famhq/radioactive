Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

Player = require '../models/player'
PlayersDaily = require '../models/player_daily'
Clan = require '../models/clan'
Group = require '../models/group'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
ClashRoyalePlayer = require '../models/clash_royale_player'
ClashRoyalePlayerDaily = require '../models/clash_royale_player_daily'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
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
  'friendly', 'clanMate', '2v2',
]
# DECK_TRACKED_GAME_TYPES = [
#   'PvP', 'classicChallenge', 'grandChallenge', 'tournament', '2v2'
# ]

DEBUG = true
IS_TEST_RUN = true and config.ENV is config.ENVS.DEV

class ClashRoyalePlayerService
  filterMatches: ({matches, player}) ->
    # only grab matches since the last update time
    matches = _.filter matches, (match) ->
      unless match
        return false
      {battleTime, battleType} = match

      if player.data?.lastMatchTime
        lastMatchTime = new Date player.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      (battleType in ALLOWED_GAME_TYPES) and
        (
          IS_TEST_RUN or
          moment(battleTime).toDate().getTime() >
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

  processMatches: ({matches, reqPlayers}) ->
    if _.isEmpty matches
      console.log 'no matches'
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
        losers = opponent
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

      # get rid of iconUrls (wasted space)
      match.team = _.map match.team, (player) ->
        _.defaults {
          cards: _.map player.cards, (card) ->
            _.omit card, ['iconUrls']
        }, player
      match.opponent = _.map match.opponent, (player) ->
        _.defaults {
          cards: _.map player.cards, (card) ->
            _.omit card, ['iconUrls']
        }, player


      # don't need to block for this
      CacheService.set key, true, {expireSeconds: SIX_HOURS_S}

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
        time: moment(match.battleTime).toDate()
      }

    start = Date.now()

    try
      Promise.all [
        ClashRoyalePlayer.batchUpsertCounterByMatches formattedMatches
        .catch (err) -> console.log 'player err', err
        .then -> console.log '---player', Date.now() - start

        ClashRoyalePlayerDaily.batchUpsertCounterByMatches formattedMatches
        .catch (err) -> console.log 'playerdaily err', err
        .then -> console.log '---playerdaily', Date.now() - start

        Match.batchCreate formattedMatches
        .catch (err) -> console.log 'match err', err
        .then -> console.log '---match', Date.now() - start

        ClashRoyalePlayerRecord.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'playerrecord err', err
        .then -> console.log '---gr', Date.now() - start

        ClashRoyalePlayerDeck.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'playerDeck err', err
        .then -> console.log '---pdeck', Date.now() - start

        ClashRoyaleDeck.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'decks err', err
        .then -> console.log '---deck', Date.now() - start

        ClashRoyaleCard.batchUpsertByMatches formattedMatches
        .catch (err) -> console.log 'cards err', err
        .then -> console.log '---card', Date.now() - start
      ]
      .then ->
        console.log 'processed'
        formattedMatches
      .catch (err) -> console.log err
    catch err
      console.log err

  updatePlayerMatches: ({matches, isBatched, tag}) =>
    if _.isEmpty matches
      return Promise.resolve null

    if isBatched
      tags = _.map matches, 'tag'
    else
      tags = [tag]

    start = Date.now()
    filteredMatches = null

    # get before update so we have accurate lastMatchTime
    Player.getAllByPlayerIdsAndGameId tags, GAME_ID
    .then (players) =>
      (if isBatched
        Promise.map(players, (player) =>
          chunkMatches = _.find(matches, {tag: player.id})?.matches
          @filterMatches {matches: chunkMatches, player}
        ).then _.flatten
      else
        @filterMatches {matches, player: players[0]})
      .then (filteredMatches) =>
        @processMatches {
          matches: filteredMatches, reqPlayers: players
        }
        .then (matches) ->
          unless _.isEmpty matches
            Player.upsertByPlayerIdAndGameId players[0].id, GAME_ID, {
              data: _.defaults {
                lastMatchTime: _.last(matches).time
              }, players[0].data
            }

  updatePlayerById: (playerId, {userId, isLegacy, priority} = {}) =>
    start = Date.now()
    ClashRoyaleAPIService.isInvalidTagInCache 'player', playerId
    .then (isInvalid) ->
      if isInvalid
        throw new Error 'invalid tag'
      Promise.all [
        ClashRoyaleAPIService.getPlayerDataByTag playerId, {priority, isLegacy}
        ClashRoyaleAPIService.getPlayerMatchesByTag playerId, {priority}
        .catch -> null
      ]
    .catch (err) -> console.log 'err, err', err
    .then ([playerData, matches]) =>
      unless playerId and playerData
        console.log 'update missing tag or data', playerId, playerData
        throw new Error 'unable to find that tag'
      unless matches
        console.log 'matches error', playerId

      if DEBUG
        console.log 'api requests', Date.now() - start
        start = Date.now()

      Promise.all [
        @updatePlayerData {userId: userId, id: playerId, playerData}
        .then ->
          if DEBUG
            console.log 'player data updated', Date.now() - start

        @updatePlayerMatches {tag: playerId, matches}
        .then ->
          if DEBUG
            console.log 'player matches updated', Date.now() - start
      ]
      .then ->
        true # notify auto_refresher of success

  updatePlayerData: ({userId, playerData, id}) =>
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
          @sendDailyPush {playerId: id}
          .catch (err) ->
            console.log 'push err', err
        , {expireSeconds: ONE_DAY_S}
        null # don't need to block

  _setClan: ({clanId, userId}) ->
    Clan.getByClanIdAndGameId clanId, GAME_ID, {
      preferCache: true
    }
    .then (clan) ->
      if clan?.groupId
        Group.addUser clan.groupId, userId
      if not clan?.data and clanId
        ClashRoyaleAPIService.refreshByClanId clanId, {userId}
        .timeout CLAN_TIMEOUT_MS
        .catch (err) ->
          console.log 'clan refresh err', err
          null

  updateAutoRefreshPlayers: =>
    key = CacheService.KEYS.AUTO_REFRESH_MAX_REVERSED_PLAYER_ID
    CacheService.get key
    .then (minReversedPlayerId) ->
      minReversedPlayerId ?= '0'
      console.log 'min', minReversedPlayerId
      # TODO: add a check to make sure this is always running. healtcheck?
      Player.getAutoRefreshByGameId GAME_ID, minReversedPlayerId
      .then (players) ->
        console.log 'p', players
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
          .catch (err) -> null
    .then (responses) =>
      successes = _.filter(responses).length
      console.log 'successes', successes
      key = CacheService.KEYS.AUTO_REFRESH_SUCCESS_COUNT
      CacheService.set key, successes, {expireSeconds: ONE_MINUTE_SECONDS}
      # TODO: make sure this doesn't cause memory leak.
      # i think the null prevents it
      @updateAutoRefreshPlayers()
      null

  sendDailyPush: ({playerId}) ->
    yesterday = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
      'day'
      moment().subtract 1, 'day'
    )
    Promise.all [
      Player.getByPlayerIdAndGameId playerId, GAME_ID
      .then EmbedService.embed {
        embed: [
          EmbedService.TYPES.PLAYER.USER_IDS
          EmbedService.TYPES.PLAYER.CHEST_CYCLE
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
        countUntilNextGoodChest = nextGoodChest.index + 1

        if playerCounter = _.find playerCounters, {gameType: 'all'}
          text = "#{countUntilNextGoodChest} chests until a
            #{_.startCase(nextGoodChest?.name)}.
            You had #{playerCounter.wins} wins and
            #{playerCounter.losses} losses today."
        else
          text = "#{countUntilNextGoodChest} chests until a
            #{_.startCase(nextGoodChest?.name)}."

        unless _.isEmpty player.userIds
          Promise.map player.userIds, User.getById
          .map (user) ->
            PushNotificationService.send user, {
              title: 'Daily recap'
              type: PushNotificationService.TYPES.DAILY_RECAP
              url: "https://#{config.SUPERNOVA_HOST}"
              text: text
              data: {path: '/'}
            }
        null

  getTopPlayers: ->
    request "#{config.CR_API_URL}/players/top", {json: true}

  updateTopPlayers: =>
    @getTopPlayers().then (topPlayers) =>
      Promise.map topPlayers, (player, index) =>
        rank = index + 1
        playerId = player.playerTag
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
