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
EmailService = require './email'
CacheService = require './cache'
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

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
PLAYER_DATA_STALE_TIME_S = 3600 * 24 # 24hr
PLAYER_MATCHES_STALE_TIME_S = 60 * 60 # 1 hour
# FIXME: temp fix so queue doesn't grow forever
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
ONE_DAY_S = 3600 * 24
SIX_HOURS_S = 3600 * 6
ONE_HOUR_SECONDS = 60
ONE_DAY_MS = 3600 * 24 * 1000
PLAYER_DATA_TIMEOUT_MS = 10000
PLAYER_MATCHES_TIMEOUT_MS = 5000
CLAN_TIMEOUT_MS = 5000
MATCHES_BATCH_REQUEST_SIZE = 50
DATA_BATCH_REQUEST_SIZE = 10
GAME_ID = config.CLASH_ROYALE_ID

ALLOWED_GAME_TYPES = [
  'PvP', 'tournament',
  'classicChallenge', 'grandChallenge'
  'friendly', 'clanMate', '2v2',
]
DECK_TRACKED_GAME_TYPES = [
  'PvP', 'classicChallenge', 'grandChallenge', 'tournament', '2v2'
]

DEBUG = false
IS_TEST_RUN = false and config.ENV is config.ENVS.DEV

class ClashRoyalePlayer
  getMatchPlayerData: ({player, deckId}) ->
    _.defaults {deckId}, player

  createNewPlayerDecks: (matches, playerDiffs) ->
    playerDecks = _.filter _.flatten _.map matches, (match) ->
      {battleType, team, opponent} = match
      _.filter _.flatten _.map team.concat(opponent), (player) ->
        if ENABLE_ANON_PLAYER_DECKS or playerDiffs.getAll().all[player.tag]
          cardKeys = _.map player.cards, ({name}) ->
            ClashRoyaleCard.getKeyByName name
          [
            {
              playerId: player.tag.replace '#', ''
              deckId: ClashRoyaleDeck.getDeckId cardKeys
              type: battleType
            }
            {
              playerId: player.tag.replace '#', ''
              deckId: ClashRoyaleDeck.getDeckId cardKeys
              type: 'all'
            }
          ]
    playerDecks = _.uniqBy playerDecks, (obj) -> JSON.stringify obj
    # unique user deck per userId (not per playerId). create one for playerId
    # if no users exist yet (so it can be duplicated over to new account)

    deckIdPlayerIdTypes = _.map playerDecks, (playerDeck) ->
      _.pick playerDeck, ['deckId', 'playerId', 'type']


    ClashRoyalePlayerDeck.getAllByDeckIdAndPlayerIdAndTypes deckIdPlayerIdTypes
    .then (existingPlayerDecks) ->
      batchPlayerDecks = _.filter _.flatten _.map playerDecks, (playerDeck) ->
        {playerId, deckId, type} = playerDeck

        if not _.find existingPlayerDecks, {deckId, playerId, type}
          return {
            deckId
            playerId
            type
          }
        else
          null
      ClashRoyalePlayerDeck.batchCreate batchPlayerDecks
      .catch ->
        # if a user changes their player id, their old decks
        # are still tied to old playerId so they aren't pulled
        # into existingPlayerDecks and it tries to insert again...
        if DEBUG
          console.log 'caught dupe'

  createNewDecks: (matches, cards) ->
    deckKeys = _.uniq _.flatten _.map matches, ({team, opponent}) ->
      _.map team.concat(opponent), (player) ->
        cardKeys = _.map player.cards, ({name}) ->
          ClashRoyaleCard.getKeyByName name
        ClashRoyaleDeck.getDeckId cardKeys
    ClashRoyaleDeck.getAllByIds deckKeys
    .then (existingDecks) ->
      newDecks = _.filter deckKeys, (key) ->
        not _.find existingDecks, {id: key}

      batchDecks = _.map newDecks, (keys) ->
        keysArray = keys.split('|')
        cardIds = _.map keysArray, (key) ->
          _.find(cards, {key})?.id
        {
          id: keys
          cardIds: cardIds
          name: 'Nameless'
        }
      ClashRoyaleDeck.batchCreate batchDecks

  incrementPlayerDecks: (batchPlayerDecks, playerDiffs) ->
    Promise.all _.filter(
      _.flattenDeep _.map batchPlayerDecks, (playerDecks, playerId) ->
        if ENABLE_ANON_PLAYER_DECKS or playerDiffs.getAll().all["##{playerId}"]
          _.map playerDecks, (playerDecksType, type) ->
            _.map playerDecksType, (changes, deckId) ->
              ClashRoyalePlayerDeck.incrementAllByDeckIdAndPlayerIdAndType(
                deckId, playerId, type, changes
              )
    )

  # TODO: track by type. Need to alter id to allow type
  incrementDecks: (batchDecks) ->
    batchDecks = _.map batchDecks, (changes, deckId) -> {changes, deckId}
    groupedDecks = _.groupBy batchDecks, ({changes}) -> JSON.stringify changes
    Promise.all _.map groupedDecks, (group, key) ->
      deckIds = _.map group, 'deckId'
      ClashRoyaleDeck.incrementAllByIds(
        deckIds, group[0].changes
      )

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

    matches
  # we should always block this for db writes/reads so the queue
  # properly throttles db access
  processMatches: ({matches, reqPlayers}) ->
    matches = _.uniqBy matches, 'id'
    matches = _.orderBy matches, ['battleTime'], ['asc']
    reqPlayerIds = _.map reqPlayers, ({id}) -> "##{id}"

    Promise.map matches, (match) ->
      # playerId = match.team[0].tag.replace '#', ''
      # Match.existsByPlayerIdAndTime playerId, match.battleTime, {preferCache: true}
      matchId = match.id
      Match.existsById matchId, {preferCache: true}
      .then (existingMatch) ->
        if existingMatch and not IS_TEST_RUN then null else match
    .then _.filter
    .then (matches) =>
      if DEBUG
        console.log 'filtered matches: ' + matches.length

      cardsKey = CacheService.KEYS.CLASH_ROYALE_CARDS
      cards = CacheService.preferCache cardsKey, ->
        ClashRoyaleCard.getAll()
      , {expireSeconds: ONE_HOUR_SECONDS}

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
      batchDecks = {}

      start = Date.now()

      # FIXME FIXME: updated playerDiff userId before passing to
      # createNewPlayerDecks, so it checks for that existing deck
      Promise.all [
        cards
        playerDiffs.setInitialDiffs playerIds, reqPlayerIds
      ]
      .then ([cards, initialDiffs]) =>
        Promise.all [
          @createNewPlayerDecks matches, playerDiffs
          .catch (err) ->
            console.log 'user decks create postgres err', err
          @createNewDecks matches, cards
          .catch (err) ->
            console.log 'decks create postgres err', err
        ]
        .then ->
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
            teamUserIds = _.flatten _.map teamPlayers, (player) ->
              player.userIds

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
            opponentUserIds = _.flatten _.map opponentPlayers, (player) ->
              player.userIds

            type = match.battleType

            teamWon = match.team[0].crowns > match.opponent[0].crowns
            opponentWon = match.opponent[0].crowns > match.team[0].crowns

            _.map team.concat(opponent), (player) ->
              diff = {
                lastMatchesUpdateTime: new Date()
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
              teamPlayerIds: _.map team, ({tag}) -> tag.replace '#', ''
              opponentPlayerIds: _.map team, ({tag}) -> tag.replace '#', ''
              # player1UserIds: player1UserIds
              # player2UserIds: player2UserIds
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
              _.map team.concat(opponent), (player, i) ->
                batchClashRoyalePlayerRecords.push {
                  playerId: player.tag.replace '#', ''
                  gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                  scaledTime
                  value: player.startingTrophies + player.trophyChange
                }

            # don't need to block for any of these
            CacheService.set key, true, {expireSeconds: SIX_HOURS_S}

            if DECK_TRACKED_GAME_TYPES.indexOf(type) isnt -1
              group = [
                {
                  players: team, playerObjs: teamPlayers,
                  deckIds: teamDeckIds, state: teamDecksState
                }
                {
                  players: opponent, playerObjs: opponentPlayers,
                  deckIds: opponentDeckIds, state: opponentDecksState
                }
              ]
              _.map group, ({players, playerObjs, deckIds, state}) ->
                _.map players, (player, i) ->
                  tag = player.tag.replace '#', ''
                  deckId = deckIds[i]
                  batchPlayerDecks[tag] ?= {}

                  batchPlayerDecks[tag]['all'] ?= {}
                  batchPlayerDecks[tag]['all'][deckId] ?= {
                    wins: 0, losses: 0, draws: 0
                  }
                  batchPlayerDecks[tag]['all'][deckId][state] += 1

                  batchPlayerDecks[tag][type] ?= {}
                  batchPlayerDecks[tag][type][deckId] ?= {
                    wins: 0, losses: 0, draws: 0
                  }
                  batchPlayerDecks[tag][type][deckId][state] += 1

                  batchDecks[deckId] ?= {wins: 0, losses: 0, draws: 0}
                  batchDecks[deckId][state] += 1

        .then =>
          start = Date.now()
          Promise.all [
            # TODO: this is slowest by far. ~500-1000ms....
            # and others seem to wait for it to complete
            # (postgres pool too small?)
            Match.batchCreate batchMatches
            .catch (err) ->
              console.log 'match create postgres err', err
            .then ->
              console.log 'match', Date.now() - start
            ClashRoyalePlayerRecord.batchCreate batchClashRoyalePlayerRecords
            .catch (err) ->
              console.log 'gamerecord create postgres err', err
            .then ->
              console.log 'gr', Date.now() - start
            @incrementPlayerDecks batchPlayerDecks, playerDiffs
            .catch (err) ->
              console.log 'inc user decks postgres err', err
            .then ->
              console.log 'pdeck', Date.now() - start
            @incrementDecks batchDecks
            .catch (err) ->
              console.log 'inc decks postgres err', err
            .then ->
              console.log 'deck', Date.now() - start
          ]
          .then ->
            console.log ''

        .then ->
          {playerDiffs: playerDiffs.getAll()}

  processUpdatePlayerMatches: ({matches, isBatched, tag}) =>
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
      if isBatched
        filteredMatches = _.flatten _.map(players, (player) =>
          chunkMatches = _.find(matches, {tag: player.id})?.matches
          @filterMatches {matches: chunkMatches, player}
        )
      else
        filteredMatches = @filterMatches {matches, player: players[0]}

      @processMatches {
        matches: filteredMatches, reqPlayers: players
      }
    .then ({playerDiffs}) ->
      # no matches processed means no player diffs
      _.map tags, (tag) ->
        playerDiffs.all["##{tag}"] = _.defaults {
          lastMatchesUpdateTime: new Date()
        }, playerDiffs.all["##{tag}"]
        playerDiffs.day["##{tag}"] = _.defaults {
          lastMatchesUpdateTime: new Date()
        }, playerDiffs.day["##{tag}"]

      # combine into 1 query for inserts instead of update to 25
      {inserts, updates} = _.reduce playerDiffs.all, (obj, diff, playerId) ->
        playerId = playerId.replace '#', ''
        if diff.preExisting
          delete diff.preExisting
          delete diff.id
          # this kind of sucks because it's not atomic in postgres
          # would need to use jsonb_set
          obj.updates[playerId] = diff
        else
          obj.inserts.push _.defaults({id: playerId}, diff)
        obj
      , {inserts: [], updates: {}}
      playerInserts = inserts
      playerUpdates = updates

      {inserts, updates} = _.reduce playerDiffs.day, (obj, diff, playerId) ->
        playerId = playerId.replace '#', ''
        if diff.preExisting
          delete diff.preExisting
          delete diff.id
          obj.updates[playerId] = diff
        else
          obj.inserts.push _.defaults({id: playerId}, diff)
        obj
      , {inserts: [], updates: {}}
      playersDailyInserts = inserts
      playersDailyUpdates = updates

      Promise.all [
        Player.batchCreateByGameId GAME_ID, playerInserts
        Promise.all _.map playerUpdates, (diff, playerId) ->
          Player.updateByPlayerIdAndGameId playerId, GAME_ID, diff
        PlayersDaily.batchCreateByGameId GAME_ID, playersDailyInserts
        Promise.all _.map playersDailyUpdates, (diff, playerId) ->
          PlayersDaily.updateByPlayerIdAndGameId playerId, GAME_ID, diff
      ]
      # kue doesn't complete with object response? needs str/empty?
      .then ->
        if DEBUG and isBatched
          console.log(
            'match processing time', Date.now() - start
            isBatched, filteredMatches?.length
          )
        undefined


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
        lastDataUpdateTime: new Date()
      }

      # NOTE: any time you update, keep in mind postgress replaces
      # entire fields (data), so need to merge with old data manually
      Player.upsertByPlayerIdAndGameId id, GAME_ID, diff, {userId}
      .then =>
        if clanId and userId
          @_setClan {clanId, userId}
      .catch (err) ->
        console.log 'err', err
        null

  _setClan: ({clanId, userId}) ->
    Clan.getByClanIdAndGameId clanId, GAME_ID, {
      preferCache: true
    }
    .then (clan) ->
      if clan?.groupId
        Group.addUser clan.groupId, userId
        return clan
      else if not clan and clanId
        ClashRoyaleAPIService.refreshByClanId clanId, {userId}
        .timeout CLAN_TIMEOUT_MS
        .catch (err) ->
          console.log 'clan refresh err', err
          null

  updateStalePlayerMatches: ({force} = {}) ->
    Player.getStaleByGameId GAME_ID, {
      type: 'matches'
      staleTimeS: if force then 0 else PLAYER_MATCHES_STALE_TIME_S
    }
    .map ({id}) -> id
    .then (playerIds) ->
      if DEBUG
        console.log 'stalematch', playerIds.length
      Player.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
        lastMatchesUpdateTime: new Date()
      }
      playerIdChunks = _.chunk playerIds, MATCHES_BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}/games", {
          json: true
          qs:
            # 5 seems to be the sweet spot. 10 slows down new users too much
            chunkValue: 5 # send us back 5 users' matches at a time
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
        }
        .catch (err) ->
          console.log 'err stalePlayerMatches', err

  updateStalePlayerData: ({force} = {}) ->
    console.log 'staledata go'
    Player.getStaleByGameId GAME_ID, {
      type: 'data'
      staleTimeS: if force then 0 else PLAYER_DATA_STALE_TIME_S
    }
    .map ({id}) -> id
    .then (playerIds) ->
      if DEBUG
        console.log 'staledata', playerIds.length, new Date()
      Player.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
        lastDataUpdateTime: new Date()
      }
      playerIdChunks = _.chunk playerIds, DATA_BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        console.log 'gpd', "#{config.CR_API_URL}/players/#{tagsStr}"
        request "#{config.CR_API_URL}/players/#{tagsStr}", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
        }
        .catch (err) ->
          console.log 'err stalePlayerData', err


  processUpdatePlayerData: ({userId, id, playerData}) =>
    if DEBUG
      console.log 'process playerdata'
    unless id
      console.log 'tag doesn\'t exist updateplayerdata'
      return Promise.resolve null
    Promise.all [
      @updatePlayerData {userId, id, playerData}
      if userId
        User.getById userId
      else
        Promise.resolve null
    ]
    .tap ([player, user]) =>
      key = CacheService.PREFIXES.USER_DAILY_DATA_PUSH + ':' + id
      CacheService.runOnce key, =>
        msSinceJoin = Date.now() - user?.joinTime?.getTime()
        if user and msSinceJoin >= ONE_DAY_MS
          @sendDailyPush {playerId: id}
          .catch (err) ->
            console.log 'push err', err
      , {expireSeconds: ONE_DAY_S}
      null # don't block

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

        # TODO: figure out why some players without userIds are initially
        # setup with an updateFrequency other than none
        if _.isEmpty player.userIds
          diff = _.defaults {updateFrequency: 'none'}, player
          console.log 'no userIds, setting freq to none'
          Player.updateByPlayerIdAndGameId player.id, GAME_ID, diff
        else
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
    @getTopPlayers().then (topPlayers) ->
      Promise.map topPlayers, (player, index) ->
        rank = index + 1
        playerId = player.playerTag
        Player.getByPlayerIdAndGameId playerId, GAME_ID
        .then EmbedService.embed {
          embed: [EmbedService.TYPES.PLAYER.USER_IDS]
          gameId: GAME_ID
        }
        .then (existingPlayer) ->
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
            ClashRoyaleAPIService.updatePlayerById playerId, {
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
      .map EmbedService.embed {
        embed: [EmbedService.TYPES.PLAYER.USER_IDS]
        gameId: GAME_ID
      }

      PlayersDaily.getAllByPlayerIdsAndGameId playerIds, GAME_ID
    ]
    .then ([players, playersDaily]) =>
      _.map playerIds, (playerId) =>
        player = _.find players, {id: playerId}
        # only process existing players
        if (player and player?.updateFrequency isnt 'none') or
            reqPlayerIds.indexOf(playerId) isnt -1

          @playerDiffs['all']["##{playerId}"] = _.defaultsDeep player, {
            data: {splits: {}}, preExisting: true
          }

          playerDaily = _.find playersDaily, {id: playerId}
          @playerDiffs['day']["##{playerId}"] = _.defaultsDeep playerDaily, {
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
    # legacy
    if not splits and type is 'PvP'
      splits =
        @playerDiffs[set][id].data.splits['ladder']
    # end legacy
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
