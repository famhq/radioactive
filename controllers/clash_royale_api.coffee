_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

ClashRoyaleAPIService = require '../services/clash_royale_api'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
UserGameData = require '../models/user_game_data'
Deck = require '../models/clash_royale_deck'
Match = require '../models/clash_royale_match'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = []

class ClashRoyaleAPICtrl
  refreshByPlayerTag: ({playerTag}, {user}) ->
    Promise.all [
      ClashRoyaleAPIService.getPlayerGamesByTag playerTag
      ClashRoyaleAPIService.getPlayerDataByTag playerTag
      UserGameData.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
    ]
    .tap ([playerGames, playerData, userGameData]) ->
      UserGameData.upsertByUserIdAndGameId user.id, config.CLASH_ROYALE_ID, {
        lastUpdateTime: new Date()
        data:
          currentDeck: playerData.currentDeck
          trophies: playerData.trophies
          name: playerData.name
          clan:
            tag: playerData.clan.tag
            name: playerData.clan.name
          level: playerData.level
          stats: _.merge playerData.stats, {
            games: playerData.games
            tournamentGames: playerData.tournamentGames
            wins: playerData.wins
            losses: playerData.losses
            currentStreak: playerData.currentStreak
          }
          lastMatchTime: new Date(playerGames[0].time)
      }
    .then ([playerGames, playerData, userGameData]) ->
      matches = _.filter playerGames, ({time}) ->
        if userGameData.data.lastMatchTime
          lastMatchTime = new Date userGameData.data.lastMatchTime
        else
          lastMatchTime = 0
        # the server time isn't 100% accurate, so +- 15 seconds
        new Date(time).getTime() > (lastMatchTime + 15)

      console.log matches.length

      Promise.each matches, (match) ->
        if match.player1.playerTag is playerTag
          player1UserId = user.id
          otherPlayerTag = match.player2.playerTag
        else
          player2UserId = user.id
          otherPlayerTag = match.player1.playerTag

        Promise.all [
          Deck.getByCardKeys match.player1.cardKeys, {useCache: true}
          Deck.getByCardKeys match.player2.cardKeys, {useCache: true}
          UserGameData.getByPlayerIdAndGameId(
            otherPlayerTag, config.CLASH_ROYALE_ID
          )
        ]
        .then ([deck1, deck2, player2User]) ->
          player2UserId = player2User?.userId
          Promise.all([
            ClashRoyaleUserDeck.upsertByDeckIdAndUserId deck1.id, user.id, {
              isFavorited: true
              isCurrentDeck: true
            }
            if player2UserId
              ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
                deck2.id
                player2UserId
                {isFavorited: true, isCurrentDeck: true}
              )
          ]).then ->
            if match.player1.crowns > match.player2.crowns
              winningDeckId = deck1.id
              losingDeckId = deck2.id
              deck1State = 'win'
              deck2State = 'loss'
            else if match.player2.crowns > match.player1.crowns
              winningDeckId = deck2.id
              losingDeckId = deck1.id
              deck1State = 'loss'
              deck2State = 'winn'
            else
              winningDeckId = null
              losingDeckId = null
              deck1State = 'draw'
              deck2State = 'draw'

            Promise.all [
              ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
                deck1.id, user.id, deck1State
              )
              ClashRoyaleDeck.incrementById(deck1.id, deck1State)
              if player2UserId
                ClashRoyaleUserDeck.incrementByDeckIdAndUserId(
                  deck2.id, player2UserId, deck2State
                )
              ClashRoyaleDeck.incrementById(deck2.id, deck2State)

              Match.create {
                id: "cr-#{match.id}"
                arena: match.arena
                matchId: match.id
                player1UserId: player1UserId
                player2UserId: player2UserId
                winningDeckId: winningDeckId
                losingDeckId: losingDeckId
                player1Data:
                  deckId: deck1.id
                  crowns: match.player1.crowns
                  playerName: match.player1.playerName
                  playerTag: match.player1.playerTag
                  clanName: match.player1.clanName
                  clanTag: match.player1.clanTag
                  trophies: match.player1.trophies
                player2Data:
                  deckId: deck2.id
                  crowns: match.player2.crowns
                  playerName: match.player2.playerName
                  playerTag: match.player2.playerTag
                  clanName: match.player2.clanName
                  clanTag: match.player2.clanTag
                  trophies: match.player2.trophies
                time: match.time
              }
            ]
    .then ->
      return null

      # UserGameData.upsertByUserIdAndGameId user.id, config.CLASH_ROYALE_ID, {
      #   data:
      #
      # }

module.exports = new ClashRoyaleAPICtrl()
