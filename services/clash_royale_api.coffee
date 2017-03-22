Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

UserGameData = require '../models/user_game_data'
UserGameDailyData = require '../models/user_game_daily_data'
Group = require '../models/group'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
EmailService = require './email'
CacheService = require './cache'
GameRecord = require '../models/game_record'
Match = require '../models/clash_royale_match'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
PLAYER_DATA_STALE_TIME_MS = 3600 * 12 # 12hr
PLAYER_MATCHES_STALE_TIME_MS = 60 * 30 # half hour
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

class ClashAPIService
  getPlayerDataByTag: (tag) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}"
    request "#{config.CR_API_URL}/players/#{tag}", {json: true}
    .then (responses) ->
      responses?[0]

  getPlayerMatchesByTag: (tag) ->
    console.log 'req', "#{config.CR_API_URL}/players/#{tag}/games"
    request "#{config.CR_API_URL}/players/#{tag}/games", {json: true}
    .then (responses) ->
      responses?[0]

  getClanDataByTag: (tag) ->
    request "#{config.CR_API_URL}/clans/#{tag}", {json: true}

  getMatchPlayerData: ({player, deck}) ->
    {
      deckId: deck.id
      crowns: player.crowns
      playerName: player.playerName
      playerTag: player.playerTag
      clanName: player.clanName
      clanTag: player.clanTag
      trophies: player.trophies
    }

  upsertUserDecks: ({deckId, userIds, playerId}) ->
    console.log '=========', userIds
    # unique user deck per userId (not per playerId). create one for playerId
    # if no users exist yet (so it can be duplicated over to new account)
    if _.isEmpty userIds
      ClashRoyaleUserDeck.upsertByDeckIdAndPlayerId(
        deckId
        playerId
        {
          isFavorited: true
          playerId: playerId
        }
      )
    else
      Promise.map userIds, (userId) ->
        ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
          deckId
          userId
          {
            isFavorited: true
            playerId: playerId
          }
        )

  # matches from API, tag, userId for adding new user to matches
  # userGameData so we can only pull in matches since last update
  processMatches: ({matches, tag, userGameData}) =>
    # only grab matches since the last update time
    matches = _.filter matches, ({time}) ->
      if userGameData.data?.lastMatchTime
        lastMatchTime = new Date userGameData.data.lastMatchTime
      else
        lastMatchTime = 0
      # the server time isn't 100% accurate, so +- 15 seconds
      new Date(time).getTime() > (new Date(lastMatchTime).getTime() + 15)
    matches = _.orderBy matches, ['time'], ['asc']

    console.log matches.length

    # store diffs in here so we can update once after all the matches are
    # processed, instead of once per match
    playerDiffs = new PlayerSplitsDiffs()

    Promise.map matches, (match) ->
      matchId = "cr-#{match.id}"
      Match.getById matchId, {preferCache: true}
      .then (existingMatch) ->
        if existingMatch then null else match
    .then _.filter
    .each (match) =>
      matchId = "cr-#{match.id}"

      player1Tag = match.player1.playerTag
      player2Tag = match.player2.playerTag

      # prefer from cached diff obj
      # (that has been modified for stats, winStreak, etc...)
      player1UserGameData = playerDiffs.getCachedById player1Tag
      player2UserGameData = playerDiffs.getCachedById player2Tag

      type = match.type

      Promise.all [
        # grab decks
        ClashRoyaleDeck.getByCardKeys match.player1.cardKeys, {
          preferCache: true
        }
        ClashRoyaleDeck.getByCardKeys match.player2.cardKeys, {
          preferCache: true
        }

        Promise.resolve player1UserGameData
        Promise.resolve player2UserGameData
      ]
      .then ([deck1, deck2, player1UserGameData, player2UserGameData]) =>
        player1UserIds = player1UserGameData.userIds
        player2UserIds = player2UserGameData.userIds

        Promise.all [
          @upsertUserDecks {
            deckId: deck1.id, userIds: player1UserIds, playerId: player1Tag
          }
          @upsertUserDecks {
            deckId: deck2.id, userIds: player2UserIds, playerId: player2Tag
          }
        ]
        .then =>
          player1Won = match.player1.crowns > match.player2.crowns
          player2Won = match.player2.crowns > match.player1.crowns

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
            playerDiffs.setById {
              id: player1Tag, field: 'currentLossStreak'
              value: 0, type: type
            }

            playerDiffs.incById {
              id: player2Tag, field: 'losses', type: type
            }
            playerDiffs.incById {
              id: player2Tag, field: 'currentLossStreak', type: type
            }
            playerDiffs.setById {
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
            playerDiffs.setById {
              id: player2Tag, field: 'currentLossStreak'
              value: 0, type: type
            }

            playerDiffs.incById {
              id: player1Tag, field: 'losses', type: type
            }
            playerDiffs.incById {
              id: player1Tag, field: 'currentLossStreak', type: type
            }
            playerDiffs.setById {
              id: player1Tag, field: 'currentWinStreak'
              value: 0, type: type
            }
          else
            winningDeckId = null
            losingDeckId = null
            deck1State = 'draw'
            deck2State = 'draw'

            playerDiffs.incById {id: player1Tag, field: 'draws', type: type}
            playerDiffs.setById {
              id: player1Tag, field: 'currentWinStreak'
              value: 0, type: type
            }
            playerDiffs.setById {
              id: player1Tag, field: 'currentLossStreak'
              value: 0, type: type
            }

            playerDiffs.incById {id: player2Tag, field: 'draws', type: type}
            playerDiffs.setById {
              id: player2Tag, field: 'currentWinStreak'
              value: 0, type: type
            }
            playerDiffs.setById {
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

          Promise.all(_.filter(_.map(player1UserIds, (userId) ->
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to user decks
            ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
              deck1.id, userId, deck1State
            )
          ).concat _.map(player2UserIds, (userId) ->
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to user decks
            ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
              deck2.id, userId, deck2State
            )
          ).concat [
            # TODO: only update these once in bulk after all matches processed
            # add win/loss/draw to deck
            ClashRoyaleDeck.incrementById(deck1.id, deck1State)
            ClashRoyaleDeck.incrementById(deck2.id, deck2State)
          ]
          .concat if type is 'ladder'
            # graphs p1
            _.map(player1UserIds, (userId) ->
              GameRecord.create {
                userId: userId
                playerId: player1Tag
                gameRecordTypeId: config.CLASH_ROYALE_TROPHIES_RECORD_ID
                scaledTime
                value: match.player1.trophies
              }
            )
          .concat if type is 'ladder'
            # graphs p2
            _.map(player2UserIds, (userId) ->
              GameRecord.create {
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
            CacheService.deleteByKey key
            Match.create {
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
          ])

          .catch (err) ->
            console.log 'err', err
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
  getUserGameDataFromPlayerData: ({playerData}) ->
    {
      currentDeck: playerData.currentDeck
      trophies: playerData.trophies
      name: playerData.name
      clan: if playerData.clan
      then { \
        tag: playerData.clan.tag, \
        name: playerData.clan.name
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

  updatePlayerMatches: ({matches, tag}) =>
    if _.isEmpty matches
      return Promise.resolve null

    console.log matches, matches[0]
    trophies = if matches[0].player1.playerTag is tag \
               then matches[0].player1.trophies
               else matches[0].player2.trophies
    diff = {
      data:
        lastMatchTime: new Date(matches[0].time)
        trophies: trophies
      lastUpdateTime: new Date()
    }
    # get before update so we have accurate lastMatchTime
    UserGameData.getByPlayerIdAndGameId tag, GAME_ID
    .then (userGameData) =>
      Promise.all [
        UserGameData.upsertByPlayerIdAndGameId tag, GAME_ID, diff
        @processMatches {tag, matches, userGameData}
      ]
    .then ([userDataUpsert, {playerDiffs}]) ->
      Promise.all _.map(playerDiffs.all, (diff, playerId) ->
        UserGameData.upsertByPlayerIdAndGameId playerId, GAME_ID, diff
      ).concat _.map playerDiffs.day, (diff, playerId) ->
        UserGameDailyData.upsertByPlayerIdAndGameId playerId, GAME_ID, diff

  updatePlayerData: ({userId, playerData, tag}) =>
    console.log 'update player data', tag
    unless tag and playerData
      return Promise.resolve null

    diff = {
      lastUpdateTime: new Date()
      playerId: tag
      data: @getUserGameDataFromPlayerData {playerData}
    }

    UserGameData.removeUserId userId, GAME_ID
    .then ->
      UserGameData.upsertByPlayerIdAndGameId tag, GAME_ID, diff, {userId}
    .then ->
      UserGameData.getByPlayerIdAndGameId tag, GAME_ID
    # technically current deck is just the most recently used one...

    # .tap (userGameData) ->
    #   ClashRoyaleUserDeck.resetCurrentByPlayerId tag
    # .tap (userGameData) =>
    #   Promise.map userGameData.userIds, (userId) =>
    #     @storeCurrentDeck {playerData, userId: userId}

  updateStalePlayerMatches: ({force} = {}) ->
    UserGameData.getStaleByGameId GAME_ID, {
      staleTimeMs: if force then 0 else PLAYER_MATCHES_STALE_TIME_MS
    }
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      console.log 'updating', playerIds
      # TODO: problem with this is if job errors, that user never gets
      # updated ever again
      # UserGameData.updateByPlayerIdsAndGameId playerIds, GAME_ID, {
      #   isQueued: true
      # }
      playerIdChunks = _.chunk playerIds, BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}/games", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerMatches"
        }

  updateStalePlayerData: ({force} = {}) ->
    UserGameData.getStaleByGameId GAME_ID, {
      staleTimeMs: if force then 0 else PLAYER_DATA_STALE_TIME_MS
    }
    .map ({playerId}) -> playerId
    .then (playerIds) ->
      playerIdChunks = _.chunk playerIds, BATCH_REQUEST_SIZE
      Promise.map playerIdChunks, (playerIds) ->
        tagsStr = playerIds.join ','
        request "#{config.CR_API_URL}/players/#{tagsStr}", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updatePlayerData"
        }

class PlayerSplitsDiffs
  constructor: ->
    @playerDiffs = {all: {}, day: {}}

  getAll: =>
    @playerDiffs

  getCachedById: (playerId) =>
    if @playerDiffs['all'][playerId]
      Promise.resolve @playerDiffs['all'][playerId]
    else
      Promise.all [
        UserGameData.getByPlayerIdAndGameId(
          playerId, GAME_ID
        )
        UserGameDailyData.getByPlayerIdAndGameId(
          playerId, GAME_ID
        )
      ]
      .then ([data, dailyData]) =>
        @playerDiffs['all'][playerId] = _.defaultsDeep data, {
          data: {splits: {}}
        }
        @playerDiffs['day'][playerId] = _.defaultsDeep dailyData, {
          data: {splits: {}}
        }
        @playerDiffs['all'][playerId]

  getCachedSplits: ({id, type, set}) =>
    splits =  @playerDiffs[set][id].data.splits[type]
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

  setById: ({id, field, type, value, set}) =>
    if set
      @getCachedSplits({id, type, set})[field] = value
    else
      _.map @playerDiffs, (diffs, set) =>
        @getCachedSplits({id, type, set})[field] = value

  setStreak: ({id, type, maxField, currentField}) =>
    _.map @playerDiffs, (diffs, set) =>
      max = @getFieldById {id, field: maxField, type, set}
      current = @getFieldById {id, field: currentField, type, set}
      if current > max
        @setById {
          id: id, field: maxField
          value: current, type: type, set: set
        }

module.exports = new ClashAPIService()
