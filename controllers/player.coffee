_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'
randomSeed = require 'random-seed'

User = require '../models/user'
UserFollower = require '../models/user_follower'
Player = require '../models/player'
ClashRoyalePlayer = require '../models/clash_royale_player'
ClashRoyaleTopPlayer = require '../models/clash_royale_top_player'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleCard = require '../models/clash_royale_card'
UserPlayer = require '../models/user_player'
Clan = require '../models/clan'
Group = require '../models/group'
ChatMessage = require '../models/chat_message'
Conversation = require '../models/conversation'
Language = require '../models/language'
ClashRoyaleAPIService = require '../services/clash_royale_api'
ClashRoyalePlayerService = require '../services/clash_royale_player'
CacheService = require '../services/cache'
TagConverterService = require '../services/tag_converter'
PushNotificationService = require '../services/push_notification'
EmbedService = require '../services/embed'
cardIds = require '../resources/data/card_ids'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.PLAYER.HI
  EmbedService.TYPES.PLAYER.COUNTERS
]
userIdsEmbed = [
  EmbedService.TYPES.PLAYER.USER_IDS
  EmbedService.TYPES.PLAYER.VERIFIED_USER
]

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
TEN_MINUTES_SECONDS = 10 * 60
ONE_MINUTE_SECONDS = 60
MAX_PLAYER_STALE_TIME_MS = 60 * 60 * 1000 # 1hr
GET_UPDATED_PLAYER_TIMEOUT_MS = 15000 # 15s

class PlayerCtrl
  getByUserIdAndGameId: ({userId, gameId}, {user}) ->
    unless userId
      return

    gameId or= GAME_ID

    # TODO: cache, but need to clear the cache whenever player is updated...
    Player.getByUserIdAndGameId userId, gameId #, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed}

  getIsAutoRefreshByPlayerIdAndGameId: ({playerId, gameId}) ->
    Player.getIsAutoRefreshByPlayerIdAndGameId playerId, gameId

  getByPlayerIdAndGameId: ({playerId, gameId, refreshIfStale}, {user}) ->
    unless playerId
      return

    playerId = ClashRoyaleAPIService.formatHashtag playerId

    getUpdatedPlayer = ->
      ClashRoyalePlayerService.updatePlayerById playerId, {priority: 'normal'}
      .then -> Player.getByPlayerIdAndGameId playerId, gameId

    # TODO: cache, but need to clear the cache whenever player is updated...
    Player.getByPlayerIdAndGameId playerId, gameId #, {preferCache: true}
    .then (player) ->
      if player
        staleMs = Date.now() - (player.lastUpdateTime?.getTime() or 0)
        if not refreshIfStale or staleMs < MAX_PLAYER_STALE_TIME_MS
          return player
        else
          getUpdatedPlayer().timeout GET_UPDATED_PLAYER_TIMEOUT_MS
          .catch (err) ->
            player
      else
        ClashRoyalePlayerService.updatePlayerById playerId, {priority: 'normal'}
        .then -> Player.getByPlayerIdAndGameId playerId, gameId
    .then EmbedService.embed {embed: defaultEmbed}

  setAutoRefreshByGameId: ({gameId}, {user}) ->
    key = "#{CacheService.LOCK_PREFIXES.SET_AUTO_REFRESH}:#{gameId}:#{user.id}"
    CacheService.lock key, ->
      Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
      .then EmbedService.embed {
        embed: [EmbedService.TYPES.PLAYER.VERIFIED_USER]
        gameId: config.CLASH_ROYALE_ID
      }
      .then (player) ->
        if player?.verifiedUser?.id is user.id
          Player.setAutoRefreshByPlayerIdAndGameId(
            player.id, config.CLASH_ROYALE_ID
          )
    , {expireSeconds: TEN_MINUTES_SECONDS}


  getVerifyDeckId: ({}, {user}) ->
    Player.getByUserIdAndGameId user.id, GAME_ID
    .then (player) ->
      unless player
        router.throw status: 404, info: 'player not found'
      seed = user.id + ':' + player.id
      rand = randomSeed.create seed
      cardCount = player.data.cards?.length or 0
      usedIds = []
      getRandomUniqueIndex = (tries = 0) ->
        id = rand(cardCount)
        if usedIds.indexOf(id) is -1
          usedIds.push id
          id
        else if tries < 20
          getRandomUniqueIndex tries + 1
      cards = _.map _.range(8), ->
        card = player.data.cards[getRandomUniqueIndex()]
        {
          key: ClashRoyaleCard.getKeyByName card.name
          id: cardIds[ClashRoyaleCard.getKeyByName(card.name)]
        }

      {
        deckId: ClashRoyaleDeck.getDeckId _.map(cards, 'key')
        copyIds: _.map cards, 'id'
      }

  verifyMe: ({}, {user}) =>
    Promise.all [
      Player.getByUserIdAndGameId user.id, GAME_ID
      @getVerifyDeckId {}, {user}
    ]
    .then ([player, verifyDeckId]) =>
      ClashRoyaleAPIService.getPlayerDataByTag player.id, {
        priority: 'high', skipCache: true
      }
      .then (playerData) =>
        currentDeckKeys = _.map playerData.currentDeck, (card) ->
          ClashRoyaleCard.getKeyByName card.name
        currentDeckId = ClashRoyaleDeck.getDeckId currentDeckKeys

        if not currentDeckId or "#{currentDeckId}" isnt "#{verifyDeckId.deckId}"
          router.throw {status: 400, info: 'invalid deck', ignoreLog: true}

        UserPlayer.setVerifiedByUserIdAndPlayerIdAndGameId(
          user.id
          player.id
          GAME_ID
        )
        .then =>
          clanId = playerData?.clan?.tag?.replace '#', ''
          @_addToClanGroup {clanId, userId: user.id, name: playerData.name}

  _addToClanGroup: ({clanId, userId, name}) =>
    Clan.getByClanIdAndGameId clanId, GAME_ID, {
      preferCache: true
    }
    .then (clan) =>
      if clan?.groupId
        Group.getById clan.groupId
        .then EmbedService.embed {embed: [EmbedService.TYPES.GROUP.USER_IDS]}
        .then (group) =>
          if group?.userIds and group.userIds.indexOf(userId) is -1
            @_addGroupUser {clan, group, userId, name}
        .catch (err) ->
          console.log err

  _addGroupUser: ({clan, group, userId, name}) ->
    Group.addUser clan.groupId, userId
    .then ->
      Conversation.getAllByGroupId clan.groupId
      .then (conversations) ->
        ChatMessage.upsert
          userId: userId
          body: '*' + Language.get('backend.userJoinedChatMessage', {
            language: group.language or 'en'
            replacements: {name}
          }) + '*'
          conversationId: conversations[0].id
          groupId: clan?.groupId
    .then ->
      message =
        titleObj:
          key: 'newClanMember.title'
        type: PushNotificationService.TYPES.GROUP
        textObj:
          key: 'newClanMember.text'
          replacements: {name}
        data:
          path:
            key: 'groupChat'
            params:
              gameKey: config.DEFAULT_GAME_KEY
              id: group.id

      PushNotificationService.sendToGroup group, message, {
        skipMe: true, userId
      }


  search: ({playerId}, {user, headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    playerId = playerId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = ClashRoyaleAPIService.isValidTag playerId
    console.log 'search', playerId, ip
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{playerId}"
    CacheService.preferCache key, ->
      Player.getByPlayerIdAndGameId playerId, GAME_ID
      .then EmbedService.embed {
        embed: userIdsEmbed
        gameId: GAME_ID
      }
      .then (player) ->
        if player?.userIds?[0]
          player.userId = player.verifiedUser?.id or player.userIds?[0]
          delete player.userIds
          player
        else
          User.create {}
          .then ({id}) ->
            start = Date.now()
            ClashRoyalePlayerService.updatePlayerById playerId, {
              userId: id
              priority: 'normal'
            }
            .then ->
              Player.getByPlayerIdAndGameId playerId, GAME_ID
              .then EmbedService.embed {
                embed: userIdsEmbed
                gameId: GAME_ID
              }
              .then (player) ->
                if player?.userIds?[0]
                  player.userId = player.verifiedUser?.id or player.userIds?[0]
                  delete player.userIds
                  player

    , {expireSeconds: TWELVE_HOURS_SECONDS}

  getTop: ->
    key = CacheService.KEYS.PLAYERS_TOP
    CacheService.preferCache key, ->
      ClashRoyaleTopPlayer.getAll()
      .then (topPlayers) ->
        playerIds = _.map topPlayers, 'playerId'
        Player.getAllByPlayerIdsAndGameId(
          playerIds, GAME_ID
        )
        .map EmbedService.embed {
          embed: userIdsEmbed
          gameId: GAME_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            player.userId = player.verifiedUser?.id or player.userIds?[0]
            delete player.userIds
            player.data = _.pick player.data, ['clan', 'name', 'trophies']
            player.data.clan = _.pick player.data.clan, ['name']
            topPlayer = _.find topPlayers, {playerId: player.id}
            {rank: topPlayer?.rank, player}
          _.orderBy players, 'rank'
    , {expireSeconds: ONE_MINUTE_SECONDS}

  getMeFollowing: ({}, {user}) ->
    key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING_PLAYERS}:#{user.id}"

    CacheService.preferCache key, ->
      UserFollower.getAllByUserId user.id
      .map (userFollower) ->
        userFollower.followingId
      .then (followingIds) ->
        Player.getAllByUserIdsAndGameId(
          followingIds, GAME_ID
        )
        .map EmbedService.embed {
          embed: userIdsEmbed
          gameId: GAME_ID
        }
        .then (players) ->
          players = _.map players, (player) ->
            player.userId = player.verifiedUser?.id or player.userIds?[0]
            delete player.userIds
            {player}
    , {expireSeconds: ONE_MINUTE_SECONDS}

module.exports = new PlayerCtrl()
