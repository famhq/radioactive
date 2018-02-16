_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

USER_PLAYERS_TABLE = 'user_players'
USER_ID_GAME_KEY_INDEX = 'userIdGameId'
PLAYER_ID_GAME_KEY_INDEX = 'playerIdGameId'
PLAYER_ID_GAME_KEY_IS_VERIFIED_INDEX = 'playerIdGameIdIsVerified'

defaultUserPlayer = (userPlayer) ->
  unless userPlayer?
    return null

  _.defaults userPlayer, {
    userId: null
    gameKey: 'clash-royale'
    playerId: null
    isVerified: false
  }

defaultUserPlayerOutput = (userPlayer) ->
  unless userPlayer?
    return null

  if userPlayer.userId
    userPlayer.userId = "#{userPlayer.userId}"
  if userPlayer.gameKey
    userPlayer.gameKey = "#{userPlayer.gameKey}"
  if userPlayer.playerId
    userPlayer.playerId = "#{userPlayer.playerId}"

  userPlayer

tables = [
  {
    name: 'user_players_by_userId_new'
    keyspace: 'starfire'
    fields:
      gameKey: 'text'
      userId: 'uuid'
      playerId: 'text'
      isVerified: 'boolean'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['gameKey', 'playerId']
  }
  {
    name: 'user_players_by_gameKey_and_playerId'
    keyspace: 'starfire'
    fields:
      gameKey: 'text'
      userId: 'uuid'
      playerId: 'text'
      isVerified: 'boolean'
    primaryKey:
      partitionKey: ['gameKey', 'playerId']
      clusteringColumns: ['userId']
  }
]

class UserPlayerModel
  SCYLLA_TABLES: tables

  upsert: (userPlayer) ->
    userPlayer = defaultUserPlayer userPlayer

    # HACK: FIXME: rm all craps cknex adds
    set = _.omit userPlayer, ['gameKey', 'userId', 'playerId']
    delete set.get
    delete set.values
    delete set.keys
    delete set.forEach

    Promise.all [
      cknex().update 'user_players_by_userId_new'
      .set set
      .where 'gameKey', '=', userPlayer.gameKey
      .andWhere 'userId', '=', userPlayer.userId
      .andWhere 'playerId', '=', userPlayer.playerId
      .run()

      cknex().update 'user_players_by_gameKey_and_playerId'
      .set set
      .where 'gameKey', '=', userPlayer.gameKey
      .andWhere 'playerId', '=', userPlayer.playerId
      .andWhere 'userId', '=', userPlayer.userId
      .run()
    ]
    .then ->
      userPlayer

  deleteByUserIdAndGameKey: (userId, gameKey) =>
    @getByUserIdAndGameKey userId, gameKey
    .then (userPlayer) =>
      if userPlayer
        @deleteByUserPlayer

  deleteByUserPlayer: (userPlayer) ->
    Promise.all [
      cknex().delete()
      .from 'user_players_by_userId_new'
      .where 'gameKey', '=', userPlayer.gameKey
      .andWhere 'userId', '=', userPlayer.userId
      .andWhere 'playerId', '=', userPlayer.playerId
      .run()

      cknex().delete()
      .from 'user_players_by_gameKey_and_playerId'
      .where 'gameKey', '=', userPlayer.gameKey
      .andWhere 'playerId', '=', userPlayer.playerId
      .andWhere 'userId', '=', userPlayer.userId
      .run()
    ]

  getByUserIdAndGameKey: (userId, gameKey) =>
    cknex().select '*'
    .from 'user_players_by_userId_new'
    .where 'gameKey', '=', gameKey
    .andWhere 'userId', '=', userId
    .run {isSingle: true}

    # TODO: rm after 3/1/2018
    .then (userPlayer) =>
      if userPlayer
        return userPlayer
      else
        cknex().select '*'
        .from 'user_players_by_userId'
        .where 'gameId', '=', config.LEGACY_CLASH_ROYALE_ID
        .andWhere 'userId', '=', userId
        .run {isSingle: true}
        .then (userPlayer) =>
          unless userPlayer
            return null
          delete userPlayer.gameId
          userPlayer.gameKey = 'clash-royale'
          @upsert userPlayer
          .then ->
            userPlayer

    .then defaultUserPlayer

  getVerifiedByPlayerIdAndGameKey: (playerId, gameKey) =>
    @getAllByPlayerIdAndGameKey playerId, gameKey
    .then (userPlayers) ->
      _.find userPlayers, {isVerified: true}

  setVerifiedByUserIdAndPlayerIdAndGameKey: (userId, playerId, gameKey) =>
    # mark others unverified
    @getVerifiedByPlayerIdAndGameKey playerId, gameKey
    .then (userPlayer) =>
      if userPlayer
        @upsert _.defaults({isVerified: false}, userPlayer)
    .then =>
      @upsert {
        userId
        playerId
        gameKey
        isVerified: true
      }
    .then ->
      key = CacheService.PREFIXES.PLAYER_VERIFIED_USER + ':' + playerId
      CacheService.deleteByKey key

  getAllByPlayerIdAndGameKey: (playerId, gameKey) =>
    # TODO: rm user_players_by_userId part after 3/1/2018
    Promise.all [
      cknex().select '*'
      .from 'user_players_by_gameKey_and_playerId'
      .where 'gameKey', '=', gameKey
      .andWhere 'playerId', '=', playerId
      .run()

      cknex().select '*'
      .from 'user_players_by_playerId'
      .where 'gameId', '=', config.LEGACY_CLASH_ROYALE_ID
      .andWhere 'playerId', '=', playerId
      .run()
    ]
    .then ([userPlayers, legacyUserPlayers]) =>
      migratePlayers = _.differenceBy legacyUserPlayers, userPlayers, 'userId'
      migratePlayers = _.map migratePlayers, (userPlayer) ->
        delete userPlayer.gameId
        userPlayer.gameKey = 'clash-royale'
        userPlayer

      userPlayers = (userPlayers or []).concat migratePlayers

      Promise.map migratePlayers, @upsert
      .then ->
        userPlayers

    .map defaultUserPlayer

  getAllByUserId: (userId) =>
    # TODO: rm user_players_by_userId part after 3/1/2018
    Promise.all [
      cknex().select '*'
      .from 'user_players_by_userId_new'
      .where 'userId', '=', userId
      .run()

      cknex().select '*'
      .from 'user_players_by_userId'
      .where 'gameId', '=', config.LEGACY_CLASH_ROYALE_ID
      .andWhere 'userId', '=', userId
      .run()
    ]
    .then ([userPlayers, legacyUserPlayers]) =>
      migratePlayers = _.differenceBy legacyUserPlayers, userPlayers, 'playerId'
      migratePlayers = _.map migratePlayers, (userPlayer) ->
        delete userPlayer.gameId
        userPlayer.gameKey = 'clash-royale'
        userPlayer

      userPlayers = (userPlayers or []).concat migratePlayers

      Promise.map migratePlayers, @upsert
      .then ->
        userPlayers

    .map defaultUserPlayer

  getAllByPlayerIdsAndGameKey: (playerIds, gameKey) ->
    playerIds = _.take playerIds, 100 # just in case

    # TODO: use 'in' version after 3/1/2018
    # cknex().select '*'
    # .from 'user_players_by_gameKey_and_playerId'
    # .where 'gameKey', '=', gameKey
    # .andWhere 'playerId', 'in', playerIds
    # .run()
    # .map defaultUserPlayer

    Promise.map playerIds, (playerId) =>
      @getAllByPlayerIdAndGameKey playerId, gameKey
      .map _.concat

  getAllByUserIdsAndGameKey: (userIds, gameKey) ->
    userIds = _.take userIds, 100 # just in case

    # TODO: use 'in' version after 3/1/2018
    # cknex().select '*'
    # .from 'user_players_by_userId_new'
    # .where 'gameKey', '=', gameKey
    # .andWhere 'userId', 'in', userIds
    # .run()
    # .map defaultUserPlayer

    Promise.map userIds, (userId) =>
      @getByUserIdAndGameKey userId, gameKey
      .map _.concat

  # migrateAll: =>
  #   CacheService = require '../services/cache'
  #   r = require '../services/rethinkdb'
  #   start = Date.now()
  #   Promise.all [
  #     CacheService.get 'migrate_user_players_min_id4'
  #     .then (minId) =>
  #       minId ?= '0'
  #       cknex().select '*'
  #       .from 'user_players_by_playerId'
  #       .where 'gameId', '=', config.LEGACY_CLASH_ROYALE_ID
  #       .andWhere 'playerId', '>', minId
  #       .run()
  #       .then (userPlayers) =>
  #         Promise.map userPlayers, (userPlayer) =>
  #           delete userPlayer.gameId
  #           userPlayer.gameKey = 'clash-royale'
  #           @upsert userPlayer
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate user_player', Date.now() - start, minId, _.last(userPlayers)?.id
  #           CacheService.set 'migrate_user_players_min_id4', _.last(userPlayers)?.id
  #           .then ->
  #             _.last(userPlayers)?.id
  #
  #     CacheService.get 'migrate_user_players_max_id4'
  #     .then (maxId) =>
  #       maxId ?= 'zzzz'
  #       cknex().select '*'
  #       .from 'user_players_by_playerId'
  #       .where 'gameId', '=', config.LEGACY_CLASH_ROYALE_ID
  #       .andWhere 'playerId', '<', maxId
  #       .run()
  #       .then (userPlayers) =>
  #         Promise.map userPlayers, (userPlayer) =>
  #           delete userPlayer.gameId
  #           userPlayer.gameKey = 'clash-royale'
  #           @upsert userPlayer
  #         .catch (err) ->
  #           console.log err
  #         .then ->
  #           console.log 'migrate user_player desc', Date.now() - start, maxId, _.last(userPlayers)?.id
  #           CacheService.set 'migrate_user_players_max_id4', _.last(userPlayers)?.id
  #           .then ->
  #             _.last(userPlayers)?.id
  #       ]
  #
  #   .then ([l1, l2]) =>
  #     if l1 and l2 and l1 < l2
  #       @migrateAll()

module.exports = new UserPlayerModel()
