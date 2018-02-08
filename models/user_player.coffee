_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

USER_PLAYERS_TABLE = 'user_players'
USER_ID_GAME_ID_INDEX = 'userIdGameId'
PLAYER_ID_GAME_ID_INDEX = 'playerIdGameId'
PLAYER_ID_GAME_ID_IS_VERIFIED_INDEX = 'playerIdGameIdIsVerified'

defaultUserPlayer = (userPlayer) ->
  unless userPlayer?
    return null

  _.defaults userPlayer, {
    userId: null
    gameId: null
    playerId: null
    isVerified: false
  }

# scylla: user_players_by_userId, user_players_by_playerId

tables = [
  {
    name: 'user_players_by_userId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      gameId: 'uuid'
      playerId: 'text'
      isVerified: 'boolean'
    primaryKey:
      partitionKey: ['gameId', 'userId']
      clusteringColumns: ['playerId']
  }
  {
    name: 'user_players_by_playerId'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      gameId: 'uuid'
      playerId: 'text'
      isVerified: 'boolean'
    primaryKey:
      partitionKey: ['gameId', 'playerId']
      clusteringColumns: ['userId']
  }
]

class UserPlayer
  SCYLLA_TABLES: tables

  upsert: (userPlayer) ->
    userPlayer = defaultUserPlayer userPlayer

    Promise.all [
      cknex().update 'user_players_by_userId'
      .set _.omit userPlayer, ['gameId', 'userId', 'playerId']
      .where 'gameId', '=', userPlayer.gameId
      .andWhere 'userId', '=', userPlayer.userId
      .andWhere 'playerId', '=', userPlayer.playerId
      .run()

      cknex().update 'user_players_by_playerId'
      .set _.omit userPlayer, ['gameId', 'playerId', 'userId']
      .where 'gameId', '=', userPlayer.gameId
      .andWhere 'playerId', '=', userPlayer.playerId
      .andWhere 'userId', '=', userPlayer.userId
      .run()
    ]
    .then ->
      userPlayer

  deleteByUserIdAndGameId: (userId, gameId) =>
    @getByUserIdAndGameId userId, gameId
    .then @deleteByUserPlayer

  deleteByUserPlayer: (userPlayer) ->
    Promise.all [
      cknex().delete()
      .from 'user_players_by_userId'
      .where 'gameId', '=', userPlayer.gameId
      .andWhere 'userId', '=', userPlayer.userId
      .andWhere 'playerId', '=', userPlayer.playerId
      .run()

      cknex().delete()
      .from 'user_players_by_playerId'
      .where 'gameId', '=', userPlayer.gameId
      .andWhere 'playerId', '=', userPlayer.playerId
      .andWhere 'userId', '=', userPlayer.userId
      .run()
    ]

  getByUserIdAndGameId: (userId, gameId) ->
    cknex().select '*'
    .from 'user_players_by_userId'
    .where 'gameId', '=', gameId
    .andWhere 'userId', '=', userId
    .run {isSingle: true}
    .then defaultUserPlayer

  getVerifiedByPlayerIdAndGameId: (playerId, gameId) =>
    @getAllByPlayerIdAndGameId playerId, gameId
    .then (userPlayers) ->
      _.filter userPlayers, {isVerified: true}

  setVerifiedByUserIdAndPlayerIdAndGameId: (userId, playerId, gameId) =>
    # mark others unverified
    @getVerifiedByPlayerIdAndGameId playerId, gameId
    .then (userPlayer) =>
      @upsert _.defaults({isVerified: false}, userPlayer)
    .then =>
      @upsert {
        userId
        playerId
        gameId
        isVerified: true
      }
    .then ->
      key = CacheService.PREFIXES.PLAYER_VERIFIED_USER + ':' + playerId
      CacheService.deleteByKey key

  getAllByPlayerIdAndGameId: (playerId, gameId) ->
    cknex().select '*'
    .from 'user_players_by_playerId'
    .where 'gameId', '=', gameId
    .andWhere 'playerId', '=', playerId
    .run()
    .map defaultUserPlayer

  getAllByPlayerIdsAndGameId: (playerIds, gameId) ->
    playerIds = _.take playerIds, 100 # just in case

    cknex().select '*'
    .from 'user_players_by_playerId'
    .where 'gameId', '=', gameId
    .andWhere 'playerId', 'in', playerIds
    .run()
    .map defaultUserPlayer

  getAllByUserIdsAndGameId: (userIds, gameId) ->
    userIds = _.take userIds, 100 # just in case

    cknex().select '*'
    .from 'user_players_by_userId'
    .where 'gameId', '=', gameId
    .andWhere 'userId', 'in', userIds
    .run()
    .map defaultUserPlayer

  migrateAll: =>
    CacheService = require '../services/cache'
    r = require '../services/rethinkdb'
    start = Date.now()
    Promise.all [
      CacheService.get 'migrate_user_players_min_id3'
      .then (minId) =>
        minId ?= '0'
        r.table 'user_players'
        .between minId, 'zzzz'
        .orderBy {index: r.asc('id')}
        .limit 500
        .then (userPlayers) =>
          Promise.map userPlayers, (userPlayer) =>
            userPlayer = _.pick userPlayer, ['userId', 'gameId', 'playerId', 'isVerified']
            @upsert userPlayer
          .catch (err) ->
            console.log err
          .then ->
            console.log 'migrate user_player', Date.now() - start, minId, _.last(userPlayers)?.id
            CacheService.set 'migrate_user_players_min_id3', _.last(userPlayers)?.id
            .then ->
              _.last(userPlayers)?.id

      CacheService.get 'migrate_user_players_max_id3'
      .then (maxId) =>
        maxId ?= 'zzzz'
        r.table 'user_players'
        .between '0000', maxId
        .orderBy {index: r.desc('id')}
        .limit 500
        .then (userPlayers) =>
          Promise.map userPlayers, (userPlayer) =>
            userPlayer = _.pick userPlayer, ['userId', 'gameId', 'playerId', 'isVerified']
            @upsert userPlayer
          .catch (err) ->
            console.log err
          .then ->
            console.log 'migrate user_player desc', Date.now() - start, maxId, _.last(userPlayers)?.id
            CacheService.set 'migrate_user_players_max_id3', _.last(userPlayers)?.id
            .then ->
              _.last(userPlayers)?.id
        ]

    .then ([l1, l2]) =>
      if l1 and l2 and l1 < l2
        @migrateAll()

module.exports = new UserPlayer()
