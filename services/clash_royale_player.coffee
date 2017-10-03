Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

Player = require '../models/player'
PlayersDaily = require '../models/player_daily'
Clan = require '../models/clan'
Group = require '../models/group'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
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

class ClashRoyalePlayer
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
    matches = _.orderBy matches, ['battleTime'], ['asc']
    reqPlayerIds = _.map reqPlayers, ({id}) -> "##{id}"

    if DEBUG
      console.log 'filtered matches: ' + matches.length

    # store diffs in here so we can update once after all the matches are
    # processed, instead of once per match
    playerIds = _.uniq _.flatten _.map matches, (match) ->
      _.map match.team.concat(match.opponent), (player) ->
        player.tag

    playerDiffs = new PlayerSplitsDiffs()
    # batch
    batchClashRoyalePlayerRecords = []
    batchMatches = []
    batchPlayerDecks = {}

    playerDiffs.setInitialDiffs playerIds, reqPlayerIds
    .then (initialDiffs) =>
      # needs to be each for streak to work
      Promise.each matches, (match, i) ->
        matchId = match.id

        team = match.team
        teamPlayers = _.filter _.map team, (player) ->
          playerDiffs.getCachedById player.tag
        teamDeckIds = _.map team, (player) ->
          cardKeys = _.map player.cards, ({name}) ->
            ClashRoyaleCard.getKeyByName name
          ClashRoyaleDeck.getDeckId cardKeys
        teamCardIds = _.flatten _.map team, (player) ->
          _.map player.cards, ({name}) ->
            ClashRoyaleCard.getKeyByName name

        opponent = match.opponent
        opponentPlayers = _.filter _.map opponent, (player) ->
          playerDiffs.getCachedById player.tag
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

        _.map team.concat(opponent), (player) ->
          diff = {
            lastUpdateTime: new Date()
            data:
              lastMatchTime: moment(match.battleTime).toDate()
          }
          if type is 'PvP'
            diff.data.trophies = player.trophies
          playerDiffs.setDiffById player.tag, diff

          playerDiffs.incById {
            id: player.tag
            field: 'crownsEarned'
            amount: player.crowns
            type: type
          }
          playerDiffs.incById {
            id: player.tag
            field: 'crownsLost'
            amount: player.crowns
            type: type
          }

        if teamWon
          winningDeckIds = teamDeckIds
          losingDeckIds = opponentDeckIds
          drawDeckIds = null
          winningDeckCardIds = teamCardIds
          losingDeckCardIds = opponentCardIds
          drawDeckCardIds = null
          teamDecksState = 'wins'
          opponentDecksState = 'losses'
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
          teamDecksState = 'losses'
          opponentDecksState = 'wins'
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
          teamDecksState = 'draws'
          opponentDecksState = 'draws'
          winners = null
          losers = null
          draws = team.concat opponent

        winningPlayerIds = _.map winners, (player) ->
          ClashRoyaleAPIService.formatHashtag player.tag
        losingPlayerIds = _.map losers, (player) ->
          ClashRoyaleAPIService.formatHashtag player.tag
        drawPlayerIds = _.map draws, (player) ->
          ClashRoyaleAPIService.formatHashtag player.tag

        _.map winners, (player) ->
          playerDiffs.incById {id: player.tag, field: 'wins', type: type}
          playerDiffs.incById {
            id: player.tag, field: 'currentWinStreak', type: type
          }
          playerDiffs.setSplitStatById {
            id: player.tag, field: 'currentLossStreak'
            value: 0, type: type
          }

        _.map losers, (player) ->
          playerDiffs.incById {
            id: player.tag, field: 'losses', type: type
          }
          playerDiffs.incById {
            id: player.tag, field: 'currentLossStreak', type: type
          }
          playerDiffs.setSplitStatById {
            id: player.tag, field: 'currentWinStreak'
            value: 0, type: type
          }

        _.map draws, (player) ->
          playerDiffs.incById {id: player.tag, field: 'draws', type: type}
          playerDiffs.setSplitStatById {
            id: player.tag, field: 'currentWinStreak'
            value: 0, type: type
          }
          playerDiffs.setSplitStatById {
            id: player.tag, field: 'currentLossStreak'
            value: 0, type: type
          }

        _.map team.concat(opponent), (player) ->
          playerDiffs.setStreak {
            id: player.tag, maxField: 'maxWinStreak'
            currentField: 'currentWinStreak', type: type
          }
          playerDiffs.setStreak {
            id: player.tag, maxField: 'maxLossStreak'
            currentField: 'currentLossStreak', type: type
          }

        # for records (graph)
        scaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
          'minute', moment(match.battleTime)
        )

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

        matchObj = {
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
          time: moment(match.battleTime).toDate()
        }
        batchMatches.push matchObj

        if type is 'PvP'
          _.forEach team.concat(opponent), (player, i) ->
            batchClashRoyalePlayerRecords.push {
              playerId: player.tag.replace '#', ''
              gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
              scaledTime
              value: player.startingTrophies + player.trophyChange
            }

        # don't need to block for any of these
        CacheService.set key, true, {expireSeconds: SIX_HOURS_S}

      .then ->
        start = Date.now()
        Promise.all [
          Player.batchUpsertByGameId GAME_ID, playerDiffs.getAll().all
          .catch (err) -> console.log 'player err', err
          .then -> console.log '---player', Date.now() - start

          PlayersDaily.batchUpsertByGameId GAME_ID, playerDiffs.getAll().day
          .catch (err) -> console.log 'playerdaily err', err
          .then -> console.log '---playerdaily', Date.now() - start

          Match.batchCreate batchMatches
          .catch (err) -> console.log 'match err', err
          .then -> console.log '---match', Date.now() - start

          ClashRoyalePlayerRecord.batchUpsert batchClashRoyalePlayerRecords
          .catch (err) -> console.log 'playerrecord err', err
          .then -> console.log '---gr', Date.now() - start

          ClashRoyalePlayerDeck.batchUpsertByMatches batchMatches
          .catch (err) -> console.log 'playerDeck err', err
          .then -> console.log '---pdeck', Date.now() - start

          ClashRoyaleDeck.batchUpsertByMatches batchMatches
          .catch (err) -> console.log 'decks err', err
          .then -> console.log '---deck', Date.now() - start

          ClashRoyaleCard.batchUpsertByMatches batchMatches
          .catch (err) -> console.log 'cards err', err
          .then -> console.log '---card', Date.now() - start
        ]
        .then ->
          console.log 'processed'
          null
      .catch (err) -> console.log err

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

  updatePlayerById: (playerId, {userId, isLegacy, priority} = {}) =>
    console.log 'update player', playerId
    Promise.all [
      ClashRoyaleAPIService.getPlayerDataByTag playerId, {priority, isLegacy}
      ClashRoyaleAPIService.getPlayerMatchesByTag playerId, {priority}
      .catch -> null
    ]
    .then ([playerData, matches]) =>
      unless playerId and playerData
        console.log 'update missing tag or data', playerId, playerData
        throw new Error 'unable to find that tag'
      unless matches
        console.log 'matches error', playerId

      @updatePlayerData {userId: userId, id: playerId, playerData}
      .then =>
        @updatePlayerMatches {tag: playerId, matches}
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

      # NOTE: any time you update, keep in mind postgress replaces
      # entire fields (data), so need to merge with old data manually
      Player.upsertByPlayerIdAndGameId id, GAME_ID, diff, {userId}
      .then =>
        if clanId and userId
          @_setClan {clanId, userId}
      .catch (err) ->
        console.log 'upsert err', err
        null

      .then ->
        if userId
          User.getById userId
        else
          Promise.resolve null
      .then (user) =>
        key = CacheService.PREFIXES.USER_DAILY_DATA_PUSH + ':' + id
        CacheService.runOnce key, =>
          msSinceJoin = Date.now() - user?.joinTime?.getTime()
          if user and msSinceJoin >= ONE_DAY_MS
            @sendDailyPush {playerId: id}
            .catch (err) ->
              console.log 'push err', err
        , {expireSeconds: ONE_DAY_S}

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
    Promise.all [
      Player.getByPlayerIdAndGameId playerId, GAME_ID
      .then EmbedService.embed {
        embed: [
          EmbedService.TYPES.PLAYER.USER_IDS
          EmbedService.TYPES.PLAYER.CHEST_CYCLE
        ]
        gameId: GAME_ID
      }
      PlayersDaily.getByPlayerIdAndGameId playerId, GAME_ID
    ]
    .then ([player, playerDaily]) ->
      if player
        goodChests = ['giantChest', 'epicChest', 'legendaryChest',
                      'superMagicalChest', 'magicalChest']
        goodChests = _.map goodChests, (chest) ->
          _.find player.data.upcomingChests?.items, {name: _.startCase(chest)}
        nextGoodChest = _.minBy goodChests, 'index'
        countUntilNextGoodChest = nextGoodChest.index + 1

        if playerDaily
          splits = playerDaily.data.splits
          stats = _.reduce splits, (aggregate, split, gameType) ->
            aggregate.wins += split.wins
            aggregate.losses += split.losses
            aggregate
          , {wins: 0, losses: 0}
          PlayersDaily.deleteByPlayerIdAndGameId(
            playerDaily.id
            GAME_ID
          )
          text = "#{countUntilNextGoodChest} chests until a
            #{_.startCase(nextGoodChest?.name)}.
            You had #{stats.wins} wins and
            #{stats.losses} losses today."
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


class PlayerSplitsDiffs
  constructor: ->
    @playerDiffs = {all: {}, day: {}}

  setInitialDiffs: (playerIds, reqPlayerIds) =>
    playerIds = _.map _.uniq(playerIds.concat reqPlayerIds), (id) ->
      id.replace '#', ''
    Promise.all [
      Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      PlayersDaily.getAllByPlayerIdsAndGameId playerIds, GAME_ID
    ]
    .then ([players, playersDaily]) =>
      _.map playerIds, (playerId) =>
        player = _.find players, {id: playerId}
        @playerDiffs['all']["##{playerId}"] = _.defaultsDeep player, {
          id: playerId
          data: {splits: {}}, preExisting: true
        }

        playerDaily = _.find playersDaily, {id: playerId}
        @playerDiffs['day']["##{playerId}"] = _.defaultsDeep playerDaily, {
          id: playerId
          data: {splits: {}}, preExisting: Boolean playerDaily
        }

  getAll: =>
    @playerDiffs

  getCachedById: (playerId) =>
    @playerDiffs['all'][playerId]

  getCachedSplits: ({id, type, set}) =>
    unless @playerDiffs[set][id]?.data?.splits
      return
    splits = @playerDiffs[set][id].data.splits[type]
    @playerDiffs[set][id].data.splits[type] = _.defaults splits, {
      currentWinStreak: 0
      currentLossStreak: 0
      maxWinStreak: 0
      maxLossStreak: 0
      crownsEarned: 0
      crownsLost: 0
      wins: 0
      losses: 0
      draws: 0
    }
    @playerDiffs[set][id].data.splits[type]

  getFieldById: ({id, field, type, set}) =>
    unless @playerDiffs[set][id]
      return
    @getCachedSplits({id, type, set})[field]

  incById: ({id, field, type, amount}) =>
    amount ?= 1
    _.map @playerDiffs, (diffs, set) =>
      @getCachedSplits({id, type, set})?[field] += amount

  setSplitStatById: ({id, field, type, value, set}) =>
    if set
      @getCachedSplits({id, type, set})?[field] = value
    else
      _.map @playerDiffs, (diffs, set) =>
        @getCachedSplits({id, type, set})?[field] = value

  setDiffById: (id, diff) =>
    _.map @playerDiffs, (diffs, set) =>
      unless @playerDiffs[set][id]
        return
      @playerDiffs[set][id] = _.merge @playerDiffs[set][id], diff

  setStreak: ({id, type, maxField, currentField}) =>
    _.map @playerDiffs, (diffs, set) =>
      max = @getFieldById {id, field: maxField, type, set}
      current = @getFieldById {id, field: currentField, type, set}
      if current > max
        @setSplitStatById {
          id: id, field: maxField
          value: current, type: type, set: set
        }

module.exports = new ClashRoyalePlayer()
