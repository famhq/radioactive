RedisService = require './redis'
Redlock = require 'redlock'
config = require '../config'

DEFAULT_CACHE_EXPIRE_SECONDS = 3600 * 24 * 30 # 30 days
DEFAULT_LOCK_EXPIRE_SECONDS = 3600 * 24 * 40000 # 100+ years
DEFAULT_REDLOCK_EXPIRE_SECONDS = 30

class CacheService
  KEYS:
    BROADCAST_FAILSAFE: 'broadcast:failsafe'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royal_deck:queued_increments:win1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_deck:queued_increments:loss1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_deck:queued_increments:draw1'
    CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royale_user_deck:queued_increments:win1'
    CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_user_deck:queued_increments:loss1'
    CLASH_ROYALE_USER_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_user_deck:queued_increments:draw1'
    CLASH_ROYALE_CARDS: 'clash_royale:cards1'
    PLAYERS_TOP: 'player:top1'
    KUE_WATCH_STUCK: 'kue:watch_stuck'
  LOCK_PREFIXES:
    KUE_PROCESS: 'kue:process'
    BROADCAST: 'broadcast'
  LOCKS: {}
  PREFIXES:
    CHAT_USER: 'chat:user9'
    THREAD_USER: 'thread:user1'
    THREAD_DECK: 'thread:deck1'
    CONVERSATION_ID: 'conversation:id'
    USER_DATA: 'user_data:id'
    USER_DATA_CONVERSATION_USERS: 'user_data:conversation_users'
    USER_DATA_FOLLOWERS: 'user_data:followers'
    USER_DATA_FOLLOWING: 'user_data:following'
    USER_DATA_FOLLOWING_PLAYERS: 'user_data:following:players'
    USER_DATA_BLOCKED_USERS: 'user_data:blocked_users'
    USER_DATA_CLASH_ROYALE_DECK_IDS: 'user_data:clash_royale_deck_ids6'
    USER_DAILY_DATA_PUSH: 'user_daily_data:push5'
    CLASH_ROYALE_MATCHES_ID: 'clash_royale_matches:id84'
    CLASH_ROYALE_CARD: 'clash_royale_card'
    CLASH_ROYALE_CARD_KEY: 'clash_royale_card_key1'
    CLASH_ROYALE_CARD_RANK: 'clash_royal_card:rank'
    CLASH_ROYALE_DECK_RANK: 'clash_royal_deck:rank'
    CLASH_ROYALE_DECK_CARD_KEYS: 'clash_royal_deck:card_keys11'
    CLASH_ROYALE_USER_DECK_DECK: 'clash_royale_user_deck:deck5'
    CLASH_ROYALE_USER_DECK_DECK_ID_USER_ID:
      'clash_royale_user_deck:deck_id:user_id'
    CLASH_ROYALE_USER_DECK_DECK_ID_PLAYER_ID:
      'clash_royale_user_deck:deck_id:player_id'
    CLASH_ROYALE_USER_DECK_PLAYER_ID:
      'clash_royale_user_deck:player_id'
    CLASH_ROYALE_API_GET_TAG: 'clash_royale_api:get_tag'
    USERNAME_SEARCH: 'username:search'
    RATE_LIMIT_CHAT_MESSAGES_TEXT: 'rate_limit:chat_messages:text'
    RATE_LIMIT_CHAT_MESSAGES_MEDIA: 'rate_limit:chat_messages:media'
    PLAYER_SEARCH: 'player:search6'
    PLAYER_VERIFIED_USER: 'player:verified_user'
    PLAYER_USER_ID_GAME_ID: 'player:user_id_game_id1'
    PLAYER_USER_IDS: 'player:user_ids1'
    PLAYER_CLASH_ROYALE_ID: 'player:clash_royale_id'
    PLAYER_MIGRATE: 'player:migrate07'
    USER_RECORDS_MIGRATE: 'user_records:migrate9'
    USER_PLAYER_USER_ID_GAME_ID: 'user_player:user_id_game_id3'
    GROUP_CLAN_CLAN_ID_GAME_ID: 'group_clan:clan_id_game_id4'
    CLAN_CLAN_ID_GAME_ID: 'clan:clan_id_game_id3'
    CLAN_MIGRATE: 'clan:migrate9'

  constructor: ->
    @redlock = new Redlock [RedisService], {
      driftFactor: 0.01
      retryCount: 0
      # retryDelay:  200
    }

  arrayAppend: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.rpush key, JSON.stringify value

  arrayGet: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.lrange key, 0, -1

  set: (key, value, {expireSeconds} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.set key, JSON.stringify value
    .then ->
      if expireSeconds
        RedisService.expire key, expireSeconds

  get: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.get key
    .then (value) ->
      try
        JSON.parse value
      catch err
        value

  # for locking
  runOnce: (key, fn, {expireSeconds, lockedFn} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_LOCK_EXPIRE_SECONDS
    # TODO: use redlock
    setVal = '1'
    RedisService.set key, setVal, 'NX', 'EX', expireSeconds
    .then (value) ->
      if value isnt null
        fn()
      else
        lockedFn?()


  lock: (key, fn, {expireSeconds, unlockWhenCompleted} = {}) =>
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_REDLOCK_EXPIRE_SECONDS
    @redlock.lock key, expireSeconds * 1000
    .then (lock) ->
      fn(lock)?.tap? ->
        if unlockWhenCompleted
          lock.unlock()
    .catch (err) ->
      # console.log 'redlock err', err
      null

  preferCache: (key, fn, {expireSeconds, ignoreNull} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_CACHE_EXPIRE_SECONDS

    RedisService.get key
    .then (value) ->
      if value?
        return JSON.parse value

      fn().then (value) ->
        if value isnt null or not ignoreNull
          RedisService.set key, JSON.stringify value
          .then ->
            RedisService.expire key, expireSeconds

        return value

  deleteByKey: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.del key

module.exports = new CacheService()
