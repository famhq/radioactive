Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

UserGameData = require '../models/user_game_data'
UserGameDailyData = require '../models/user_game_daily_data'
Group = require '../models/group'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
EmailService = require './email'
CacheService = require './cache'
GameRecord = require '../models/game_record'
PushNotificationService = require '../services/push_notification'
KueCreateService = require '../services/kue_create'
Match = require '../models/clash_royale_match'
User = require '../models/user'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
PLAYER_DATA_STALE_TIME_S = 3600 * 12 # 12hr
PLAYER_MATCHES_STALE_TIME_S = 60 * 60 # 1 hour
# FIXME: temp fix so queue doesn't grow forever
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

processingM = 0
processingP = 0

class ClashAPIService
  getPlayerDataByTag: (tag, {priority} = {}) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}"
    request "#{config.CR_API_URL}/players/#{tag}", {
      json: true
      qs:
        priority: priority
    }
    .then (responses) ->
      responses?[0]
    .catch (err) ->
      console.log 'err playerDataByTag'
      console.log err

  getPlayerMatchesByTag: (tag) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}/games"
    request "#{config.CR_API_URL}/players/#{tag}/games", {json: true}
    .then (responses) ->
      responses?[0]
    .catch (err) ->
      console.log 'err playerMatchesByTag'
      console.log err

  getClanDataByTag: (tag) ->
    request "#{config.CR_API_URL}/clans/#{tag}", {json: true}

  refreshByPlayerTag: (playerTag, {userId, priority} = {}) =>
    Promise.all [
      @getPlayerDataByTag playerTag, {priority}
      @getPlayerMatchesByTag playerTag, {priority}
    ]
    .then ([playerData, matches]) ->
      KueCreateService.createJob {
        job: {userId: userId, tag: playerTag, playerData}
        type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_DATA
        priority: priority or 'high'
        waitForCompletion: true
      }
      .then ->
        KueCreateService.createJob {
          job: {tag: playerTag, matches, reqSynchronous: true}
          type: KueCreateService.JOB_TYPES.UPDATE_PLAYER_MATCHES
          priority: priority or 'high'
          waitForCompletion: true
        }
        .timeout 5000
        .catch -> null

  getMatchPlayerData: ({player, deck}) ->
    {
      deckId: deck.id
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
    ClashRoyaleUserDeck.getAllByPlayerId playerId, {preferCache: true}
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

  # matches from API, tag, userId for adding new user to matches
  # userGameData so we can only pull in matches since last update
  processMatches: ({matches, tag, userGameData, reqSynchronous}) =>
    processingM += 1
    console.log 'processing matches', processingM
    # only grab matches since the last update time
    matches = _.filter matches, (match) ->
      unless match
        return false
      {time} = match
      if userGameData.data?.lastMatchTime
        lastMatchTime = new Date userGameData.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      new Date(time).getTime() > (new Date(lastMatchTime).getTime() + 15)
    matches = _.orderBy matches, ['time'], ['asc']

    console.log 'filtered matches: ' + matches.length + ' ' + tag + ' ' + reqSynchronous

    # store diffs in here so we can update once after all the matches are
    # processed, instead of once per match
    playerIds = _.flatten _.map matches, (match) ->
      [match.player1.playerTag, match.player2.playerTag]
    playerDiffs = new PlayerSplitsDiffs()
    # batch
    batchGameRecords = []
    batchMatches = []

    start = Date.now()

    @cachedGetDeckFns = {}
    @cachedUpsertUserDeckFns = {}

    playerDiffs.setInitialDiffs playerIds
    .then ->
      Promise.map matches, (match) ->
        matchId = "cr-#{match.id}"
        Match.getById matchId, {preferCache: true}
        .then (existingMatch) ->
          if existingMatch then null else match
    .then _.filter
    # needs to be each for streak to work
    .each (match) =>
      matchId = "cr-#{match.id}"

      player1Tag = match.player1.playerTag
      player2Tag = match.player2.playerTag

      # prefer from cached diff obj
      # (that has been modified for stats, winStreak, etc...)
      player1UserGameData = playerDiffs.getCachedById player1Tag
      player2UserGameData = playerDiffs.getCachedById player2Tag

      player1CardKeys = ClashRoyaleDeck.getCardKeys match.player1.cardKeys
      player2CardKeys = ClashRoyaleDeck.getCardKeys match.player2.cardKeys
      @cachedGetDeckFns[player1CardKeys] ?=
        ClashRoyaleDeck.getByCardKeys match.player1.cardKeys, {
          preferCache: true
        }
      @cachedGetDeckFns[player2CardKeys] ?=
        ClashRoyaleDeck.getByCardKeys match.player2.cardKeys, {
          preferCache: true
        }

      type = match.type

      Promise.all [
        # grab decks
        @cachedGetDeckFns[player1CardKeys]
        @cachedGetDeckFns[player2CardKeys]
      ]
      .then (responses) =>
        [deck1, deck2] = responses
        console.log 'm1', Date.now() - start, player1Tag, player2Tag
        start = Date.now()
        player1UserIds = player1UserGameData.userIds
        player2UserIds = player2UserGameData.userIds

        @cachedUpsertUserDeckFns["#{deck1.id}-#{player1Tag}"] ?=
          @upsertUserDecks {
            deckId: deck1.id, userIds: player1UserIds, playerId: player1Tag
          }

        @cachedUpsertUserDeckFns["#{deck2.id}-#{player2Tag}"] ?=
          @upsertUserDecks {
            deckId: deck2.id, userIds: player2UserIds, playerId: player2Tag
          }

        Promise.all [
          @cachedUpsertUserDeckFns["#{deck1.id}-#{player1Tag}"]
          @cachedUpsertUserDeckFns["#{deck2.id}-#{player2Tag}"]
        ]
        .then =>
          start = Date.now()
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
            winningDeckId = deck1.id
            losingDeckId = deck2.id
            winningDeckCardIds = deck1.cardIds
            losingDeckCardIds = deck2.cardIds
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
            winningDeckId = deck2.id
            losingDeckId = deck1.id
            winningDeckCardIds = deck2.cardIds
            losingDeckCardIds = deck1.cardIds
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

          start = Date.now()
          Promise.all [
            ClashRoyaleUserDeck.incrementByDeckIdAndPlayerId(
              deck1.id, player1Tag, deck1State, {batch: not reqSynchronous}
            )
            ClashRoyaleUserDeck.incrementByDeckIdAndPlayerId(
              deck2.id, player2Tag, deck2State, {batch: not reqSynchronous}
            )
          ].concat [
            ClashRoyaleDeck.incrementById deck1.id, deck1State, {
              batch: not reqSynchronous
            }
            ClashRoyaleDeck.incrementById deck2.id, deck2State, {
              batch: not reqSynchronous
            }
          ].concat(if type is 'ladder'
            # graphs p1
            _.map(player1UserIds, (userId) ->
              batchGameRecords.push {
                userId: userId
                playerId: player1Tag
                gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                scaledTime
                value: match.player1.trophies
              }
            )
          ).concat(if type is 'ladder'
            # graphs p2
            _.map(player2UserIds, (userId) ->
              batchGameRecords.push {
                userId: userId
                playerId: player2Tag
                gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                scaledTime
                value: match.player2.trophies
              }
            )
          ).concat [
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
                player: match.player1, deck: deck1
              }
              player2Data: @getMatchPlayerData {
                player: match.player2, deck: deck2
              }
              time: new Date(match.time)
            }
            CacheService.set key, matchObj
            batchMatches.push matchObj
          ]

          .catch (err) ->
            console.log 'err', err
          .then ->
            console.log 'm4', Date.now() - start
    .then ->
      Promise.all [
        GameRecord.batchCreate batchGameRecords
        Match.batchCreate batchMatches
      ]
    .then ->
      processingM -= 1
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
  getUserGameDataFromPlayerData: ({playerData}) ->
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
    if _.isEmpty matches
      return Promise.resolve null

    # get before update so we have accurate lastMatchTime
    UserGameData.getByPlayerIdAndGameId tag, GAME_ID
    .then (userGameData) =>
      @processMatches {tag, matches, userGameData, reqSynchronous}
    .then ({playerDiffs}) ->
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
          obj.inserts.push diff
        obj
      , {inserts: [], updates: {}}
      userGameDataInserts = inserts
      userGameDataUpdates = updates

      {inserts, updates} = _.reduce playerDiffs.day, (obj, diff, playerId) ->
        if diff.id
          obj.updates[playerId] = diff
        else
          obj.inserts.push diff
        obj
      , {inserts: [], updates: {}}
      userGameDailyDataInserts = inserts
      userGameDailyDataUpdates = updates

      Promise.all [
        UserGameData.batchCreate userGameDataInserts
        Promise.all _.map userGameDataUpdates, (diff, playerId) ->
          UserGameData.updateByPlayerIdAndGameId playerId, GAME_ID, diff
        UserGameDailyData.batchCreate userGameDailyDataInserts
        Promise.all _.map userGameDailyDataUpdates, (diff, playerId) ->
          UserGameDailyData.updateByPlayerIdAndGameId playerId, GAME_ID, diff
      ]
      # kue doesn't complete with object response? needs str/empty?
      .then -> undefined

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
      data: @getUserGameDataFromPlayerData {playerData}
    }
    console.log diff

    UserGameData.removeUserId userId, GAME_ID
    .then ->
      UserGameData.upsertByPlayerIdAndGameId tag, GAME_ID, diff, {userId}
    .catch (err) ->
      console.log 'errr', err
      null
    .then ->
      processingP -= 1
    # technically current deck is just the most recently used one...

    # .tap (userGameData) ->
    #   ClashRoyaleUserDeck.resetCurrentByPlayerId tag
    # .tap (userGameData) =>
    #   Promise.map userGameData.userIds, (userId) =>
    #     @storeCurrentDeck {playerData, userId: userId}

  updateStalePlayerMatches: ({force} = {}) ->
    UserGameData.getStaleByGameId GAME_ID, {
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
      UserGameData.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
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
    UserGameData.getStaleByGameId GAME_ID, {
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
      UserGameData.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
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
    @updatePlayerData {userId, tag, playerData}
    .then (userGameData) ->
      if isDaily
        key = CacheService.PREFIXES.USER_DAILY_DATA_PUSH + ':' + tag
        CacheService.runOnce key, ->
          Promise.all [
            UserGameData.getByPlayerIdAndGameId tag, GAME_ID
            UserGameDailyData.getByPlayerIdAndGameId tag, GAME_ID
          ]
          .then ([userGameData, userGameDailyData]) ->
            if userGameData and userGameDailyData?.data
              console.log 'dailydata'
              splits = userGameDailyData.data.splits
              stats = _.reduce splits, (aggregate, split, gameType) ->
                aggregate.wins += split.wins
                aggregate.losses += split.losses
                aggregate
              , {wins: 0, losses: 0}
              UserGameDailyData.deleteById userGameDailyData.id
              Promise.map userGameData.userIds, User.getById
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
    @getTopPlayers().then (topPlayers) =>
      Promise.map topPlayers, (player, index) =>
        rank = index + 1
        playerId = player.playerTag
        UserGameData.getByPlayerIdAndGameId playerId, GAME_ID
        .then (userGameData) =>
          if userGameData?.verifiedUserId
            UserGameData.updateById userGameData.id, {
              data:
                trophies: player.trophies
                name: player.name
            }
          else
            User.create {}
            .then ({id}) =>
              userId = id
              Promise.all [
                ClashRoyaleUserDeck.duplicateByPlayerId playerId, userId
                GameRecord.duplicateByPlayerId playerId, userId
                UserGameData.upsertByPlayerIdAndGameId playerId, GAME_ID, {
                  verifiedUserId: userId
                }, {userId}
              ]
              .then =>
                @refreshByPlayerTag playerId, {
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
      UserGameData.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      UserGameDailyData.getAllByPlayerIdsAndGameId playerIds, GAME_ID
    ]
    .then ([datas, dailyDatas]) =>
      _.map playerIds, (playerId) =>
        data = _.find datas, {playerId}
        dailyData = _.find dailyDatas, {playerId}
        @playerDiffs['all'][playerId] = _.defaultsDeep data, {
          data: {splits: {}}, playerId: playerId
        }
        @playerDiffs['day'][playerId] = _.defaultsDeep dailyData, {
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

module.exports = new ClashAPIService()
