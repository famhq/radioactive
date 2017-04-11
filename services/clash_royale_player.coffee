Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

Player = require '../models/player'
PlayersDaily = require '../models/player_daily'
Clan = require '../models/clan'
Group = require '../models/group'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
EmailService = require './email'
CacheService = require './cache'
GameRecord = require '../models/game_record'
PushNotificationService = require './push_notification'
ClashRoyaleKueService = require './clash_royale_kue'
Match = require '../models/clash_royale_match'
User = require '../models/user'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
PLAYER_DATA_STALE_TIME_S = 3600 * 12 # 12hr
PLAYER_MATCHES_STALE_TIME_S = 60 * 60 # 1 hour
# FIXME: temp fix so queue doesn't grow forever
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
PLAYER_DATA_TIMEOUT_MS = 10000
PLAYER_MATCHES_TIMEOUT_MS = 5000
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

processingM = 0
processingP = 0

class ClashRoyalePlayer
  getMatchPlayerData: ({player, deckId}) ->
    {
      deckId: deckId
      crowns: player.crowns
      playerName: player.playerName
      playerTag: player.playerTag
      clanName: player.clanName
      clanTag: player.clanTag
      trophies: player.trophies
      chest: player.chest
    }

  upsertUserDecks: ({deckId, userIds, playerId, reqSynchronous}) ->
    # unique user deck per userId (not per playerId). create one for playerId
    # if no users exist yet (so it can be duplicated over to new account)
    upsertPromise = ClashRoyaleUserDeck.getAllByPlayerId playerId, {
      preferCache: true
    }
    .then (cachedUserDecks) ->
      if _.isEmpty(userIds) and not _.find cachedUserDecks, {deckId}
        ClashRoyaleUserDeck.upsertByDeckIdAndPlayerId(
          deckId
          playerId
          {
            isFavorited: true
            playerId: playerId
          }
          {durability: if reqSynchronous then 'hard' else 'soft'}
        )
      else if not _.isEmpty(userIds)
        Promise.map userIds, (userId) ->
          unless _.find cachedUserDecks, {deckId, userId}
            ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
              deckId
              userId
              {
                isFavorited: true
                playerId: playerId
              }
              {durability: if reqSynchronous then 'hard' else 'soft'}
            )
    if reqSynchronous
      upsertPromise
    else
      null # no need to block since increment decks is async

  # matches from API, tag, userId for adding new user to matches
  # player so we can only pull in matches since last update
  processMatches: ({matches, tag, player, reqSynchronous}) =>
    processingM += 1
    console.log 'processing matches', processingM
    # only grab matches since the last update time
    matches = _.filter matches, (match) ->
      unless match
        return false
      {time, type} = match

      if player.data?.lastMatchTime
        lastMatchTime = new Date player.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      type isnt 'clanBattle' and
        new Date(time).getTime() > (new Date(lastMatchTime).getTime() + 15)
    matches = _.orderBy matches, ['time'], ['asc']

    start = Date.now()
    Promise.map matches, (match) ->
      matchId = "cr-#{match.id}"
      Match.getById matchId, {preferCache: true}
      .then (existingMatch) ->
        if existingMatch then null else match
    # .then (matches) ->
    #   console.log 'm0b', Date.now() - start2
    #   matches
    .then _.filter
    .then (matches) =>
      console.log 'm0', Date.now() - start
      console.log 'filtered matches: ' + matches.length + ' ' + tag

      cardsKey = CacheService.KEYS.CLASH_ROYALE_CARDS
      cards = CacheService.preferCache cardsKey, ->
        ClashRoyaleCard.getAll()

      # store diffs in here so we can update once after all the matches are
      # processed, instead of once per match
      playerIds = _.flatten _.map matches, (match) ->
        [match.player1.playerTag, match.player2.playerTag]
      playerDiffs = new PlayerSplitsDiffs()
      # batch
      batchGameRecords = []
      batchMatches = []
      batchDecks = []

      start = Date.now()

      deckKeys = _.uniq _.flatten _.map matches, ({player1, player2}) ->
        [
          ClashRoyaleDeck.getCardKeys player1.cardKeys
          ClashRoyaleDeck.getCardKeys player2.cardKeys
        ]

      @cachedUpsertUserDeckFns = {}

      start = Date.now()
      Promise.all [
        cards
        playerDiffs.setInitialDiffs playerIds
      ]
      .then ([cards, initialDiffs]) =>
        console.log 'm1', Date.now() - start

        deckCreatePromise = ClashRoyaleDeck.getByIds deckKeys
        .then (existingDecks) ->
          newDecks = _.filter deckKeys, (key) ->
            not _.find existingDecks, {key}

          batchDecks = batchDecks.concat _.map newDecks, (keys) ->
            keysArray = keys.split('|')
            cardIds = _.map keysArray, (key) ->
              _.find(cards, {key})?.id
            {
              cardKeys: keys
              cardIds: cardIds
              name: 'Nameless'
            }
          console.log 'batchDecks', batchDecks?.length
          ClashRoyaleDeck.batchCreate batchDecks

        (if reqSynchronous
          deckCreatePromise
        else
          Promise.resolve null) # don't block
        .then =>
          # console.log 'm0', Date.now() - start
          # start2 = Date.now()
          # needs to be each for streak to work
          Promise.each matches, (match, i) =>
            matchId = "cr-#{match.id}"

            player1Tag = match.player1.playerTag
            player2Tag = match.player2.playerTag

            # prefer from cached diff obj
            # (that has been modified for stats, winStreak, etc...)
            player1Player = playerDiffs.getCachedById player1Tag
            player2Player = playerDiffs.getCachedById player2Tag

            deck1Id = ClashRoyaleDeck.getCardKeys match.player1.cardKeys
            deck2Id = ClashRoyaleDeck.getCardKeys match.player2.cardKeys

            deck1CardIds = _.map match.player1.cardKeys, (key) ->
              _.find(cards, {key})?.id
            deck2CardIds = _.map match.player2.cardKeys, (key) ->
              _.find(cards, {key})?.id

            type = match.type

            player1UserIds = player1Player.userIds
            player2UserIds = player2Player.userIds

            @cachedUpsertUserDeckFns["#{deck1Id}-#{player1Tag}"] ?=
              @upsertUserDecks {
                deckId: deck1Id, userIds: player1UserIds, playerId: player1Tag
                reqSynchronous: reqSynchronous
              }

            @cachedUpsertUserDeckFns["#{deck2Id}-#{player2Tag}"] ?=
              @upsertUserDecks {
                deckId: deck2Id, userIds: player2UserIds, playerId: player2Tag
                reqSynchronous: reqSynchronous
              }

            stepStart = Date.now()
            Promise.all [
              @cachedUpsertUserDeckFns["#{deck1Id}-#{player1Tag}"]
              @cachedUpsertUserDeckFns["#{deck2Id}-#{player2Tag}"]
            ]
            .then =>
              console.log 'm3', Date.now() - stepStart
              stepStart = Date.now()
              player1Won = match.player1.crowns > match.player2.crowns
              player2Won = match.player2.crowns > match.player1.crowns

              player1Diff = {
                lastMatchesUpdateTime: new Date()
                data:
                  lastMatchTime: new Date(match.time)
              }
              if match.type is 'ladder'
                player1Diff.data.trophies = match.player1.trophies
              playerDiffs.setDiffById player1Tag, player1Diff

              player2Diff = {
                lastMatchesUpdateTime: new Date()
                data:
                  lastMatchTime: new Date(match.time)
              }
              if match.type is 'ladder'
                player2Diff.data.trophies = match.player2.trophies
              playerDiffs.setDiffById player2Tag, player2Diff

              playerDiffs.incById {
                id: player1Tag
                field: 'crownsEarned'
                amount: match.player1.crowns
                type: type
              }
              playerDiffs.incById {
                id: player1Tag
                field: 'crownsLost'
                amount: match.player2.crowns
                type: type
              }

              playerDiffs.incById {
                id: player2Tag
                field: 'crownsEarned'
                amount: match.player2.crowns
                type: type
              }
              playerDiffs.incById {
                id: player2Tag
                field: 'crownsLost'
                amount: match.player1.crowns
                type: type
              }

              if player1Won
                winningDeckId = deck1Id
                losingDeckId = deck2Id
                winningDeckCardIds = deck1CardIds
                losingDeckCardIds = deck2CardIds
                deck1State = 'win'
                deck2State = 'loss'

                playerDiffs.incById {id: player1Tag, field: 'wins', type: type}
                playerDiffs.incById {
                  id: player1Tag, field: 'currentWinStreak', type: type
                }
                playerDiffs.setSplitStatById {
                  id: player1Tag, field: 'currentLossStreak'
                  value: 0, type: type
                }

                playerDiffs.incById {
                  id: player2Tag, field: 'losses', type: type
                }
                playerDiffs.incById {
                  id: player2Tag, field: 'currentLossStreak', type: type
                }
                playerDiffs.setSplitStatById {
                  id: player2Tag, field: 'currentWinStreak'
                  value: 0, type: type
                }
              else if player2Won
                winningDeckId = deck2Id
                losingDeckId = deck1Id
                winningDeckCardIds = deck2CardIds
                losingDeckCardIds = deck1CardIds
                deck1State = 'loss'
                deck2State = 'win'

                playerDiffs.incById {id: player2Tag, field: 'wins', type: type}
                playerDiffs.incById {
                  id: player2Tag, field: 'currentWinStreak', type: type
                }
                playerDiffs.setSplitStatById {
                  id: player2Tag, field: 'currentLossStreak'
                  value: 0, type: type
                }

                playerDiffs.incById {
                  id: player1Tag, field: 'losses', type: type
                }
                playerDiffs.incById {
                  id: player1Tag, field: 'currentLossStreak', type: type
                }
                playerDiffs.setSplitStatById {
                  id: player1Tag, field: 'currentWinStreak'
                  value: 0, type: type
                }
              else
                winningDeckId = null
                losingDeckId = null
                deck1State = 'draw'
                deck2State = 'draw'

                playerDiffs.incById {id: player1Tag, field: 'draws', type: type}
                playerDiffs.setSplitStatById {
                  id: player1Tag, field: 'currentWinStreak'
                  value: 0, type: type
                }
                playerDiffs.setSplitStatById {
                  id: player1Tag, field: 'currentLossStreak'
                  value: 0, type: type
                }

                playerDiffs.incById {id: player2Tag, field: 'draws', type: type}
                playerDiffs.setSplitStatById {
                  id: player2Tag, field: 'currentWinStreak'
                  value: 0, type: type
                }
                playerDiffs.setSplitStatById {
                  id: player2Tag, field: 'currentLossStreak'
                  value: 0, type: type
                }

              # player 1
              playerDiffs.setStreak {
                id: player1Tag, maxField: 'maxWinStreak'
                currentField: 'currentWinStreak', type: type
              }
              playerDiffs.setStreak {
                id: player1Tag, maxField: 'maxLossStreak'
                currentField: 'currentLossStreak', type: type
              }

              # player 2
              playerDiffs.setStreak {
                id: player2Tag, maxField: 'maxWinStreak'
                currentField: 'currentWinStreak', type: type
              }
              playerDiffs.setStreak {
                id: player2Tag, maxField: 'maxLossStreak'
                currentField: 'currentLossStreak', type: type
              }

              # for records (graph)
              scaledTime = GameRecord.getScaledTimeByTimeScale(
                'minute', moment(match.time)
              )

              prefix = CacheService.PREFIXES.CLASH_ROYALE_MATCHES_ID
              key = "#{prefix}:#{matchId}"
              matchObj = {
                id: matchId
                arena: match.arena
                league: match.league
                matchId: match.id
                type: match.type
                player1Id: match.player1.playerTag
                player2Id: match.player2.playerTag
                # player1UserIds: player1UserIds
                # player2UserIds: player2UserIds
                winningDeckId: winningDeckId
                losingDeckId: losingDeckId
                winningCardIds: winningDeckCardIds
                losingCardIds: losingDeckCardIds
                player1Data: @getMatchPlayerData {
                  player: match.player1, deck: deck1Id
                }
                player2Data: @getMatchPlayerData {
                  player: match.player2, deck: deck2Id
                }
                time: new Date(match.time)
              }
              batchMatches.push matchObj

              if type is 'ladder'
                # graphs p1
                _.map player1UserIds, (userId) ->
                  batchGameRecords.push {
                    userId: userId
                    playerId: player1Tag
                    gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                    scaledTime
                    value: match.player1.trophies
                  }
                # graphs p2
                _.map player2UserIds, (userId) ->
                  batchGameRecords.push {
                    userId: userId
                    playerId: player2Tag
                    gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                    scaledTime
                    value: match.player2.trophies
                  }

              CacheService.set(key, matchObj) # don't need to block for this

              stepStart = Date.now()
              Promise.all [
                ClashRoyaleUserDeck.incrementByDeckIdAndPlayerId(
                  deck1Id, player1Tag, deck1State, {batch: not reqSynchronous}
                )
                ClashRoyaleUserDeck.incrementByDeckIdAndPlayerId(
                  deck2Id, player2Tag, deck2State, {batch: not reqSynchronous}
                )
              ].concat [
                ClashRoyaleDeck.incrementById deck1Id, deck1State, {
                  batch: not reqSynchronous
                }
                ClashRoyaleDeck.incrementById deck2Id, deck2State, {
                  batch: not reqSynchronous
                }
              ]

              .catch (err) ->
                console.log 'err', err
              .then ->
                console.log 'm4', Date.now() - stepStart, reqSynchronous
        .then ->
          # don't need to block for this
          Match.batchCreate batchMatches

          processingM -= 1

          recordsCreatePromise = GameRecord.batchCreate batchGameRecords

          if reqSynchronous
            recordsCreatePromise
          else
            null

        .then ->
          {playerDiffs: playerDiffs.getAll()}

  # current deck being used
  # storeCurrentDeck: ({playerData, userId}) ->
  #   ClashRoyaleDeck.getByCardKeys _.map(playerData.currentDeck, 'key'), {
  #     preferCache: true
  #   }
  #   .then (deck) ->
  #     ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
  #       deck.id
  #       userId
  #       {isFavorited: true, isCurrentDeck: true}
  #     )

  # morph api format to our format
  getPlayerFromPlayerData: ({playerData}) ->
    {
      currentDeck: playerData.currentDeck
      trophies: playerData.trophies
      name: playerData.name
      clan: if playerData.clan
      then { \
        tag: playerData.clan.tag, \
        name: playerData.clan.name, \
        badge: playerData.clan.badge
      }
      else null
      level: playerData.level
      arena: playerData.arena
      league: playerData.league
      stats: _.merge playerData.stats, {
        games: playerData.games
        tournamentGames: playerData.tournamentGames
        wins: playerData.wins
        losses: playerData.losses
        currentStreak: playerData.currentStreak
      }
    }

  updatePlayerMatches: ({matches, tag, reqSynchronous}) =>
    console.log 'update player matches', tag, matches?.length

    if not tag or _.isEmpty matches
      return Promise.resolve null

    start = Date.now()

    # get before update so we have accurate lastMatchTime
    Player.getByPlayerIdAndGameId tag, GAME_ID
    .then (player) =>
      console.log 'matches1', Date.now() - start
      @processMatches {tag, matches, player, reqSynchronous}
    .then ({playerDiffs}) ->
      console.log 'matches2', Date.now() - start
      # no matches processed means no player diffs
      playerDiffs.all[tag] = _.defaults {
        lastMatchesUpdateTime: new Date()
      }, playerDiffs.all[tag]
      playerDiffs.day[tag] = _.defaults {
        lastMatchesUpdateTime: new Date()
      }, playerDiffs.day[tag]

      playerIds = _.keys playerDiffs.all
      # combine into 1 query for inserts instead of update to 25
      {inserts, updates} = _.reduce playerDiffs.all, (obj, diff, playerId) ->
        if diff.id
          obj.updates[playerId] = diff
        else
          obj.inserts.push _.defaults({playerId, gameId: GAME_ID}, diff)
        obj
      , {inserts: [], updates: {}}
      playerInserts = inserts
      playerUpdates = updates

      {inserts, updates} = _.reduce playerDiffs.day, (obj, diff, playerId) ->
        if diff.id
          obj.updates[playerId] = diff
        else
          obj.inserts.push _.defaults({playerId, gameId: GAME_ID}, diff)
        obj
      , {inserts: [], updates: {}}
      playersDailyInserts = inserts
      playersDailyUpdates = updates

      Promise.all [
        Player.batchCreate playerInserts
        Promise.all _.map playerUpdates, (diff, playerId) ->
          Player.updateByPlayerIdAndGameId playerId, GAME_ID, diff
        PlayersDaily.batchCreate playersDailyInserts
        Promise.all _.map playersDailyUpdates, (diff, playerId) ->
          PlayersDaily.updateByPlayerIdAndGameId playerId, GAME_ID, diff
      ]
      # kue doesn't complete with object response? needs str/empty?
      .then ->
        console.log 'matches3', Date.now() - start
        undefined

  updatePlayerData: ({userId, playerData, tag}) =>
    processingP += 1
    console.log 'processingData', processingP
    console.log 'update player data', tag
    unless tag and playerData
      processingP -= 1
      return Promise.resolve null

    diff = {
      lastUpdateTime: new Date()
      playerId: tag
      data: @getPlayerFromPlayerData {playerData}
    }

    # console.log playerData
    (if playerData?.clan?.tag
      Clan.getByClanIdAndGameId playerData.clan.tag, GAME_ID, {
        preferCache: true
      }
    else
      Promise.resolve null)
    .then (clan) ->
      if clan
        return clan
      else if playerData?.clan?.tag
        ClashRoyaleKueService.refreshByClanId playerData.clan.tag
        .catch -> null
    .then (clan) ->
      diff.clanId = clan?.id

      Player.removeUserId userId, GAME_ID
      .then ->
        Player.upsertByPlayerIdAndGameId tag, GAME_ID, diff, {userId}
      .catch (err) ->
        console.log 'errr', err
        null
      .then ->
        processingP -= 1
    # technically current deck is just the most recently used one...

    # .tap (player) ->
    #   ClashRoyaleUserDeck.resetCurrentByPlayerId tag
    # .tap (player) =>
    #   Promise.map player.userIds, (userId) =>
    #     @storeCurrentDeck {playerData, userId: userId}

  updateStalePlayerMatches: ({force} = {}) ->
    Player.getStaleByGameId GAME_ID, {
      type: 'matches'
      staleTimeS: if force then 0 else PLAYER_MATCHES_STALE_TIME_S
    }
    # .filter ({lastQueuedMatchesTime}) ->
    #   unless lastQueuedMatchesTime
    #     return true
    #   timeDiff = Date.now() - lastQueuedMatchesTime.getTime?()
    #   return timeDiff > MIN_TIME_BETWEEN_UPDATES_MS
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      console.log 'stalematch', playerIds.length, new Date()
      Player.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
        # TODO: problem with this is if job errors, that user never gets
        # updated ever again
        # isQueued: true
        # lastQueuedMatchesTime: new Date()
        lastMatchesUpdateTime: new Date()
      }
      playerIdChunks = _.chunk playerIds, BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}/games", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
        }
        .catch (err) ->
          console.log 'err stalePlayerMatches'
          console.log err

  updateStalePlayerData: ({force} = {}) ->
    Player.getStaleByGameId GAME_ID, {
      type: 'data'
      staleTimeS: if force then 0 else PLAYER_DATA_STALE_TIME_S
    }
    # .filter ({lastQueuedTime}) ->
    #   unless lastQueuedTime
    #     return true
    #   timeDiff = Date.now() - new Date(lastQueuedTime).getTime()
    #   return timeDiff > MIN_TIME_BETWEEN_UPDATES_MS
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      console.log 'staledata', playerIds.length, new Date()
      Player.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
        # TODO: problem with this is if job errors, that user never gets
        # updated ever again
        # isQueued: true
        # lastQueuedTime: new Date()
        lastUpdateTime: new Date()
      }
      playerIdChunks = _.chunk playerIds, BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
        }
        .catch (err) ->
          console.log 'err stalePlayerData'
          console.log err

  processUpdatePlayerData: ({userId, tag, playerData, isDaily}) =>
    unless tag
      console.log 'tag doesn\'t exist updateplayerdata'
      return Promise.resolve null
    console.log 'process'
    @updatePlayerData {userId, tag, playerData}
    .then (player) ->
      if isDaily
        key = CacheService.PREFIXES.USER_DAILY_DATA_PUSH + ':' + tag
        CacheService.runOnce key, ->
          Promise.all [
            Player.getByPlayerIdAndGameId tag, GAME_ID
            PlayersDaily.getByPlayerIdAndGameId tag, GAME_ID
          ]
          .then ([player, playersDaily]) ->
            if player and playersDaily?.data
              console.log 'dailydata'
              splits = playersDaily.data.splits
              stats = _.reduce splits, (aggregate, split, gameType) ->
                aggregate.wins += split.wins
                aggregate.losses += split.losses
                aggregate
              , {wins: 0, losses: 0}
              PlayersDaily.deleteById playersDaily.id
              Promise.map player.userIds, User.getById
              .map (user) ->
                PushNotificationService.send user, {
                  title: 'Daily recap'
                  type: PushNotificationService.TYPES.DAILY_RECAP
                  url: "https://#{config.SUPERNOVA_HOST}"
                  text: "#{stats.wins} wins, #{stats.losses} losses.
                        Post in chat what else you want to see in the recap :)"
                  data: {path: '/'}
                }
              null
        , {expireSeconds: TWENTY_THREE_HOURS_S}
  getTopPlayers: ->
    request "#{config.CR_API_URL}/players/top", {json: true}

  updateTopPlayers: =>
    if config.ENV is config.ENVS.DEV
      return
    @getTopPlayers().then (topPlayers) ->
      Promise.map topPlayers, (player, index) ->
        rank = index + 1
        playerId = player.playerTag
        Player.getByPlayerIdAndGameId playerId, GAME_ID
        .then (player) ->
          if player?.verifiedUserId
            Player.updateById player.id, {
              data:
                trophies: player.trophies
                name: player.name
            }
          else
            User.create {}
            .then ({id}) ->
              userId = id
              Promise.all [
                ClashRoyaleUserDeck.duplicateByPlayerId playerId, userId
                GameRecord.duplicateByPlayerId playerId, userId
                Player.upsertByPlayerIdAndGameId playerId, GAME_ID, {
                  verifiedUserId: userId
                }, {userId}
              ]
              .then ->
                ClashRoyaleKueService.efreshByPlayerTag playerId, {
                  userId: userId, priority: 'normal'
                }

        .then ->
          ClashRoyaleTopPlayer.upsertByRank rank, {
            playerId: playerId
          }


class PlayerSplitsDiffs
  constructor: ->
    @playerDiffs = {all: {}, day: {}}

  setInitialDiffs: (playerIds) =>
    Promise.all [
      Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      PlayersDaily.getAllByPlayerIdsAndGameId playerIds, GAME_ID
    ]
    .then ([players, playersDaily]) =>
      _.map playerIds, (playerId) =>
        player = _.find players, {playerId}
        playerDaily = _.find playersDaily, {playerId}
        @playerDiffs['all'][playerId] = _.defaultsDeep player, {
          data: {splits: {}}, playerId: playerId
        }
        @playerDiffs['day'][playerId] = _.defaultsDeep playerDaily, {
          data: {splits: {}}, playerId: playerId
        }

  getAll: =>
    @playerDiffs

  getCachedById: (playerId) =>
    @playerDiffs['all'][playerId]

  getCachedSplits: ({id, type, set}) =>
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
    @getCachedSplits({id, type, set})[field]

  incById: ({id, field, type, amount}) =>
    amount ?= 1
    _.map @playerDiffs, (diffs, set) =>
      @getCachedSplits({id, type, set})[field] += amount

  setSplitStatById: ({id, field, type, value, set}) =>
    if set
      @getCachedSplits({id, type, set})[field] = value
    else
      _.map @playerDiffs, (diffs, set) =>
        @getCachedSplits({id, type, set})[field] = value

  setDiffById: (id, diff) =>
    _.map @playerDiffs, (diffs, set) =>
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
