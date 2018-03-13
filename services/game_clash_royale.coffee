Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

GroupClan = require '../models/group_clan'
ClashRoyaleClanRecord = require '../models/clash_royale_clan_record'
UserPlayer = require '../models/user_player'
Player = require '../models/player'
Clan = require '../models/clan'
Language = require '../models/language'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
ClashRoyalePlayer = require '../models/clash_royale_player'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
ClashRoyaleService = require './game_clash_royale'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
CacheService = require './cache'
KueCreateService = require './kue_create'
PushNotificationService = require './push_notification'
TagConverterService = require './tag_converter'
EmbedService = require './embed'
Match = require '../models/clash_royale_match'
User = require '../models/user'
config = require '../config'

# for now we're not storing user deck info of players that aren't on fam.
# should re-enable if we can handle the added load from it.
# big issue is 2v2
ENABLE_ANON_PLAYER_DECKS = false

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
CLAN_STALE_TIME_S = 3600 * 12 # 12hr
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
AUTO_REFRESH_PLAYER_TIMEOUT_MS = 30 * 1000
API_REQUEST_TIMEOUT_MS = 10000
ONE_MINUTE_SECONDS = 60
ONE_DAY_S = 3600 * 24
SIX_HOURS_S = 3600 * 6
ONE_DAY_MS = 3600 * 24 * 1000
CLAN_TIMEOUT_MS = 5000
GAME_KEY = 'clash-royale'

ALLOWED_GAME_TYPES = [
  'PvP', 'tournament',
  'classicChallenge', 'grandChallenge'
  'friendly', 'clanMate', '2v2', 'touchdown2v2DraftPractice',
  'touchdown2v2Draft', 'newCardChallenge', '3xChallenge', 'rampUp'
  'youtubeDecks'
]

DEBUG = false or config.ENV is config.ENVS.DEV
IS_TEST_RUN = false and config.ENV is config.ENVS.DEV

class ClashRoyaleService
  filterMatches: ({matches, tag, isBatched}) =>
    tags = if isBatched then _.map matches, 'tag' else [tag]

    # get before update so we have accurate lastMatchTime
    Player.getAllByPlayerIdsAndGameKey tags, GAME_KEY
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

  processMatches: ({matches}) =>
    if _.isEmpty matches
      return Promise.resolve null
    matches = _.uniqBy matches, 'id'
    # matches = _.orderBy matches, ['battleTime'], ['asc']

    if DEBUG
      console.log 'filtered matches: ' + matches.length

    formattedMatches = _.map matches, (match, i) =>
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

      winningPlayerIds = _.map winners, (player) =>
        @formatByPlayerId player.tag
      losingPlayerIds = _.map losers, (player) =>
        @formatByPlayerId player.tag
      drawPlayerIds = _.map draws, (player) =>
        @formatByPlayerId player.tag

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
      Player.upsertByPlayerIdAndGameKey tag, GAME_KEY, {
        lastUpdateTime: new Date()
      }

    @processMatches {matches}
    .tap (matches) ->
      if tag
        Player.getByPlayerIdAndGameKey tag, GAME_KEY

  updatePlayerByPlayerId: (playerId, options = {}) =>
    {userId, isLegacy, priority, isAuto} = options
    start = Date.now()
    @isInvalidTagInCache 'player', playerId
    .then (isInvalid) =>
      if isInvalid
        throw new Error 'invalid tag'
      @getPlayerMatchesByTag playerId, {
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
          @getPlayerDataByPlayerId playerId, {
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
        console.log 'caught updatePlayerId'#, err
        throw err
    .then ->
      true # notify auto_refresher of success

  updatePlayerData: ({userId, playerData, id, lastMatchTime, isAuto}) =>
    if DEBUG
      console.log 'update player data', id
    unless id and playerData
      return Promise.resolve null

    clanId = playerData?.clan?.tag?.replace '#', ''

    Player.getByPlayerIdAndGameKey id, GAME_KEY
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
      Player.upsertByPlayerIdAndGameKey id, GAME_KEY, diff, {userId}
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

  _setClan: ({clanId, userId}) =>
    Clan.getByClanIdAndGameKey clanId, GAME_KEY, {
      preferCache: true
    }
    .then (clan) =>
      if not clan?.data and clanId
        @updateClanById clanId, {userId}
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
        Player.getAutoRefreshByGameId GAME_KEY, minReversedPlayerId
        .then (players) ->
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
    # console.log 'sending daily push', playerId, isAuto, GAME_KEY
    Promise.all [
      Player.getByPlayerIdAndGameKey playerId, GAME_KEY
      .then EmbedService.embed {
        embed: [
          EmbedService.TYPES.PLAYER.USER_IDS
        ]
        gameKey: GAME_KEY
      }
      Player.getCountersByPlayerIdAndScaledTimeAndGameKey(
        playerId, yesterday, GAME_KEY
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
            }
        null

  updateTopPlayers: =>
    @getTopPlayers().then (response) =>
      topPlayers = response?.items
      Promise.map topPlayers, (player, index) =>
        rank = index + 1
        playerId = @formatByPlayerId player.tag
        Player.getByPlayerIdAndGameKey playerId, GAME_KEY
        .then EmbedService.embed {
          embed: [EmbedService.TYPES.PLAYER.USER_IDS]
          gameKey: GAME_KEY
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
            Player.upsertByPlayerIdAndGameKey playerId, GAME_KEY, newPlayer
          else
            @updatePlayerByPlayerId playerId, {
              priority: 'normal'
            }

        .then ->
          ClashRoyaleTopPlayer.upsert {
            rank: rank
            playerId: playerId
          }

  formatByPlayerId: (hashtag) ->
    unless hashtag
      return null
    return hashtag.trim().toUpperCase()
            .replace '#', ''
            .replace /O/g, '0' # replace capital O with zero

  isValidByPlayerId: (hashtag) ->
    hashtag and hashtag.match /^[0289PYLQGRJCUV]+$/

  isInvalidTagInCache: (type, tag) ->
    unless type or tag
      return Promise.resolve false
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.get key

  setInvalidTag: (type, tag) ->
    unless type or tag
      return
    key = "#{CacheService.PREFIXES.CLASH_ROYALE_INVALID_TAG}:#{type}:#{tag}"
    CacheService.set key, true, {expireSeconds: ONE_DAY_S}

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

  getPlayerDataByPlayerId: (tag, {priority, skipCache, isLegacy} = {}) =>
    tag = @formatByPlayerId tag

    unless @isValidByPlayerId tag
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

  getPlayerMatchesByTag: (tag, {priority, skipThrow} = {}) =>
    tag = @formatByPlayerId tag

    unless @isValidByPlayerId tag
      throw new Error 'invalid tag'

    @request "/players/%23#{tag}/battlelog", {type: 'player', tag, priority}
    .then (matches) ->
      if not skipThrow and _.isEmpty matches
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
                     else if match.challengeId in [\
                       73001203, 72000051, 73001291\
                     ]
                     then 'touchdown2v2Draft'
                     else if match.challengeId is 73001324
                     then 'newCardChallenge'
                     else if match.challengeId is 73001287
                     then 'rampUp'
                     else if match.challengeId is 73001263
                     then '3xChallenge'
                     else if match.challengeId is 73001299
                     then 'youtubeDecks'
                     else match.type
        match

  getTopPlayers: (locationId) =>
    @request '/locations/global/rankings/players'

  updateClan: ({userId, clan, tag}) ->
    unless tag and clan
      return Promise.resolve null

    diff = {
      lastUpdateTime: new Date()
      clanId: tag
      data: clan
      # players: players
    }

    Clan.getByClanIdAndGameKey tag, GAME_KEY
    .then (existingClan) ->
      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        value: clan.donationsPerWeek
      }

      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        value: clan.clanScore
      }

      playerIds = _.map clan.memberList, ({tag}) -> tag.replace '#', ''
      Promise.all [
        UserPlayer.getAllByPlayerIdsAndGameKey playerIds, GAME_KEY
        Player.getAllByPlayerIdsAndGameKey playerIds, GAME_KEY
      ]
      .then ([existingUserPlayers, existingPlayers]) ->
        _.map existingPlayers, (existingPlayer) ->
          clanPlayer = _.find clan.memberList, {
            tag: "##{existingPlayer.id}"
          }
          donations = clanPlayer.donations
          clanChestCrowns = clanPlayer.clanChestPoints
          # TODO: batch these
          ClashRoyalePlayerRecord.upsert {
            playerId: existingPlayer.id
            gameRecordTypeId: config.CLASH_ROYALE_DONATIONS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            value: donations
          }
          ClashRoyalePlayerRecord.upsert {
            playerId: existingPlayer.id
            gameRecordTypeId: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            value: clanChestCrowns
          }

        newPlayers = _.filter _.map clan.memberList, (player) ->
          unless _.find existingPlayers, {id: player.tag.replace('#', '')}
            {
              id: player.tag.replace '#', ''
              data:
                name: player.name
                trophies: player.trophies
                expLevel: player.expLevel
                arena: player.arena
                clan:
                  badgeId: clan.badgeId
                  name: clan.name
                  tag: clan.tag
            }
        Player.batchUpsertByGameId GAME_KEY, newPlayers

      (if existingClan
        Clan.upsertByClanIdAndGameKey tag, GAME_KEY, diff
      else
        Clan.upsertByClanIdAndGameKey tag, GAME_KEY, diff
        .then ->
          Clan.createGroup {
            userId: userId
            name: clan.name
            clanId: diff.clanId
          }
          .then (group) ->
            GroupClan.updateByClanIdAndGameKey tag, GAME_KEY, {groupId: group.id}
      ).catch (err) ->
        console.log 'clan err', err

  getClanByTag: (tag, {priority} = {}) =>
    tag = @formatByPlayerId tag

    unless @isValidByPlayerId tag
      throw new Error 'invalid tag'

    @request "/clans/%23#{tag}", {type: 'clan', tag}
    .catch (err) ->
      console.log 'err clanByTag', err

  updateClanById: (clanId, {userId, priority} = {}) =>
    @getClanByTag clanId, {priority}
    .then (clan) =>
      @updateClan {userId: userId, tag: clanId, clan}
    .then ->
      Clan.getByClanIdAndGameKey clanId, 'clash-royale', {
        preferCache: true
      }
      .then (clan) ->
        if clan
          {id: clan?.id}

module.exports = new ClashRoyaleService()
