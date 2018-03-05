Redlock = require 'redlock'
Promise = require 'bluebird'

RedisService = require './redis'
RedisPersistentService = require './redis_persistent'
config = require '../config'

DEFAULT_CACHE_EXPIRE_SECONDS = 3600 * 24 * 30 # 30 days
DEFAULT_LOCK_EXPIRE_SECONDS = 3600 * 24 * 40000 # 100+ years
DEFAULT_REDLOCK_EXPIRE_SECONDS = 30
ONE_HOUR_SECONDS = 3600

PREFIXES =
  CHAT_USER: 'chat:user21'
  CHAT_USER_B_USERNAME: 'chat:user:byUsername'
  CHAT_GROUP_USER: 'chat:group_user5'
  THREAD_USER: 'thread:user1'
  THREAD_CREATOR: 'thread:creator3'
  THREAD: 'thread:id:embedded2'
  THREAD_BY_ID: 'thread:id2'
  THREAD_DECK: 'thread:deck11'
  THREAD_COMMENTS: 'thread:comments17'
  THREAD_COMMENT_COUNT: 'thread:comment_count1'
  THREADS_CATEGORY: 'threads5'
  CHAT_MESSAGE_DAILY_XP: 'chat_message:daily_xp'
  CONVERSATION_ID: 'conversation:id5'
  VIDEO_DAILY_XP: 'video:daily_xp'
  VIDEOS_GROUP_ID: 'videos:group_id3'
  USER_ID: 'user:id'
  USER_USERNAME: 'user:username'
  USER_FOLLOWER_COUNT: 'user:follower_count'
  USER_DATA: 'user_data:id'
  USER_DATA_CONVERSATION_USERS: 'user_data:conversation_users'
  USER_DATA_FOLLOWERS: 'user_data:followers'
  USER_DATA_FOLLOWING: 'user_data:following'
  USER_DATA_FOLLOWING_PLAYERS: 'user_data:following:players'
  USER_DATA_BLOCKED_USERS: 'user_data:blocked_users'
  USER_DATA_CLASH_ROYALE_DECK_IDS: 'user_data:clash_royale_deck_ids6'
  USER_DAILY_DATA_PUSH: 'user_daily_data:push5'
  ADDON_ID: 'addon:id'
  ADDON_KEY: 'addon:key4'
  ADDON_GET_ALL_BY_GAME_KEY: 'addon:get_all1'
  CLASH_ROYALE_MATCHES_ID: 'clash_royale_matches:id52'
  CLASH_ROYALE_MATCHES_ID_EXISTS: 'clash_royale_matches:id:exists2'
  CLASH_ROYALE_INVALID_TAG: 'clash_royale:invalid_tag'
  CLASH_ROYALE_CARD: 'clash_royale_card2'
  CLASH_ROYALE_CARD_ALL: 'clash_royale_card:all2'
  CLASH_ROYALE_CARD_KEY: 'clash_royale_card_key3'
  CLASH_ROYALE_CARD_TOP: 'clash_royal_card:top'
  CLASH_ROYALE_CARD_POPULAR_DECKS: 'clash_royal_card:popular_decks'
  CLASH_ROYALE_CARD_STATS: 'clash_royal_card:stats1'
  CLASH_ROYALE_CARD_RANK: 'clash_royal_card:rank'
  CLASH_ROYALE_DECK_RANK: 'clash_royal_deck:rank'
  CLASH_ROYALE_DECK_STATS: 'clash_royal_deck:stats1'
  CLASH_ROYALE_DECK_GET_POPULAR: 'clash_royal_deck:get_popular3'
  CLASH_ROYALE_DECK_CARD_KEYS: 'clash_royal_deck:card_keys12'
  CLASH_ROYALE_PLAYER_DECK_DECK: 'clash_royale_player_deck:deck9'
  CLASH_ROYALE_PLAYER_DECK_DECK_ID_USER_ID:
    'clash_royale_player_deck:deck_id:user_id1'
  CLASH_ROYALE_PLAYER_DECK_DECK_ID_PLAYER_ID:
    'clash_royale_player_deck:deck_id:player_id2'
  CLASH_ROYALE_PLAYER_DECK_PLAYER_ID:
    'clash_royale_player_deck:player_id2'
  CLASH_ROYALE_API_GET_PLAYER_ID: 'clash_royale_api:get_tag'
  GROUP_ID: 'group:id4'
  GROUP_KEY: 'group:key3'
  GROUP_GET_ALL: 'group:getAll16'
  GROUP_GET_ALL_CATEGORY: 'group:getAll:category9'
  GROUP_GAME_KEY_LANGUAGE: 'group:game_key_language1'
  GROUP_STAR: 'group:star2'
  GROUP_USER_COUNT: 'group:user_count1'
  GROUP_ROLE_GROUP_ID_USER_ID: 'group_role:groupId:userId3'
  GROUP_ROLES: 'group_role:groupId1'
  GROUP_USER_USER_ID: 'group_user:user_id10'
  GROUP_USER_TOP: 'group_user:top3'
  GROUP_USERS_ONLINE: 'group_users:online2'
  GROUP_USER_XP_COMPLETE_TRANSACTION: 'groupUserXp:completeTransaction'
  USERNAME_SEARCH: 'username:search1'
  RATE_LIMIT_CHAT_MESSAGES_TEXT: 'rate_limit:chat_messages:text'
  RATE_LIMIT_CHAT_MESSAGES_MEDIA: 'rate_limit:chat_messages:media'
  PLAYER_SEARCH: 'player:search8'
  PLAYER_VERIFIED_USER: 'player:verified_user6'
  PLAYER_USER_ID_GAME_KEY: 'player:user_id_game_id1'
  PLAYER_USER_IDS: 'player:user_ids2'
  CLAN_CLASH_ROYALE_ID: 'clan:clash_royale_id3'
  PLAYER_CLASH_ROYALE_ID: 'player:clash_royale_id'
  PLAYER_MIGRATE: 'player:migrate07'
  REFRESH_PLAYER_ID_LOCK: 'player:refresh_lock'
  FORTNITE_REFRESH_PLAYER_ID_LOCK: 'fortnite_player:refresh_lock1'
  THREAD_COMMENTS_THREAD_ID: 'thread_comments:thread_id17'
  TRADE_SEND_ITEMS: 'trade:send_items5'
  TRADE_RECEIVE_ITEMS: 'trade:receive_items5'
  USER_DECKS_MIGRATE: 'user_decks:migrate16'
  USER_RECORDS_MIGRATE: 'user_records:migrate11'
  USER_PLAYER_USER_ID_GAME_KEY: 'user_player:user_id_game_id1'
  GROUP_CLAN_CLAN_ID_GAME_KEY: 'group_clan:clan_id_game_id9'
  CLAN_CLAN_ID_GAME_KEY: 'clan:clan_id_game_id11'
  CLAN_MIGRATE: 'clan:migrate9'
  CLAN_PLAYERS: 'clan:players1'
  BAN_IP: 'ban:ip2'
  BAN_USER_ID: 'ban:user_id2'
  HONEY_POT_BAN_IP: 'honey_pot:ban_ip5'
  REWARD_INCREMENT: 'reward:increment'
  REWARD_ATTEMPT_TIME: 'reward_attempt:time1'
  SPECIAL_OFFER_ID: 'special_offer:id'
  USER_SPECIAL_OFFERS: 'user_special_offers9'

class CacheService
  KEYS:
    AUTO_REFRESH_MAX_REVERSED_PLAYER_ID: 'auto_refresh:max_reversed_player_id'
    AUTO_REFRESH_SUCCESS_COUNT: 'auto_refresh:success_count1'
    BROADCAST_FAILSAFE: 'broadcast:failsafe'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royal_deck:queued_increments:win1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_deck:queued_increments:loss1'
    CLASH_ROYALE_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_deck:queued_increments:draw1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_WIN:
      'clash_royale_player_deck:queued_increments:win1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_LOSS:
      'clash_royal_player_deck:queued_increments:loss1'
    CLASH_ROYALE_PLAYER_DECK_QUEUED_INCREMENTS_DRAW:
      'clash_royal_player_deck:queued_increments:draw1'
    CLASH_ROYALE_CARDS: 'clash_royale:cards1'
    PLAYERS_TOP: 'player:top1'
    SPECIAL_OFFER_ALL: 'special_offer:all2'
    KUE_WATCH_STUCK: 'kue:watch_stuck'
    STALE_THREAD_IDS: 'threads:stale_ids'
  LOCK_PREFIXES:
    KUE_PROCESS: 'kue:process'
    OPEN_PACK: 'open_pack1'
    BROADCAST: 'broadcast'
    UPGRADE_STICKER: 'upgrade_sticker2'
    SET_AUTO_REFRESH: 'set_auto_refresh4'
    CONSUME_ITEM: 'consume_item0'
    OPEN_ITEM: 'open_item2'
    SPECIAL_OFFER_DAILY: 'special_offer:daily'
    SPECIAL_OFFER_INSTALL: 'special_offer:install'
  LOCKS:
    AUTO_REFRESH: 'auto_refresh'
  PREFIXES: PREFIXES
  STATIC_PREFIXES: # these should stay, don't add a number to end to clear
    GROUP_LEADERBOARD: 'group:leaderboard'
    CARD_DECK_LEADERBOARD: 'card:deck_leaderboard'
    GAME_TYPE_DECK_LEADERBOARD: 'gameType:deck_leaderboard'
    THREAD_GROUP_LEADERBOARD_BY_CATEGORY: 'thread:group_leaderboard:by_category'
    THREAD_GROUP_LEADERBOARD_ALL: 'thread:group_leaderboard:by_all'
    ADDON_GAME_KEY_LEADERBOARD_ALL: 'addon:gameKey_leaderboard:by_all'
    PINNED_THREAD_IDS: 'pinned_thread_ids'

  constructor: ->
    @redlock = new Redlock [RedisService], {
      driftFactor: 0.01
      retryCount: 0
      # retryDelay:  200
    }

  tempSetAdd: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.sadd key, value

  tempSetGetAll: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.smembers key

  setAdd: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisPersistentService.sadd key, value

  setRemove: (key, value) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisPersistentService.srem key, value

  setGetAll: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisPersistentService.smembers key

  leaderboardUpdate: (setKey, member, score) ->
    key = config.REDIS.PREFIX + ':' + setKey
    RedisPersistentService.zadd key, score, member

  leaderboardDelete: (setKey, member) ->
    key = config.REDIS.PREFIX + ':' + setKey
    RedisPersistentService.zrem key, member

  leaderboardIncrement: (setKey, member, increment, {currentValueFn} = {}) =>
    key = config.REDIS.PREFIX + ':' + setKey
    RedisPersistentService.zincrby key, increment, member
    .tap (newValue) =>
      # didn't exist before, sync their xp just in case
      if currentValueFn and "#{newValue}" is "#{increment}"
        currentValueFn()
        .then (currentValue) =>
          if currentValue and "#{currentValue}" isnt "#{newValue}"
            @leaderboardUpdate setKey, member, currentValue
        null # don't block

  leaderboardGet: (key, {limit, skip} = {}) ->
    skip ?= 0
    limit ?= 50
    key = config.REDIS.PREFIX + ':' + key
    RedisPersistentService.zrevrange key, skip, skip + limit - 1, 'WITHSCORES'

  leaderboardTrim: (key, trimLength = 10000) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisPersistentService.zremrangebyrank key, 0, -1 * (trimLength + 1)

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

  getCursor: (cursor) =>
    key = "#{PREFIXES.CURSOR}:#{cursor}"
    @get key

  setCursor: (cursor, value) =>
    key = "#{PREFIXES.CURSOR}:#{cursor}"
    @set key, value, {expireSeconds: ONE_HOUR_SECONDS}

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
      fn(lock)?.tap?(->
        if unlockWhenCompleted
          lock.unlock()
      ).catch? (err) ->
        lock.unlock()
        throw {fnError: err}
    .catch (err) ->
      if err.fnError
        throw err.fnError
      # don't pass back other (redlock) errors

  preferCache: (key, fn, {expireSeconds, ignoreNull, category} = {}) =>
    rawKey = key
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_CACHE_EXPIRE_SECONDS

    if category
      categoryKey = 'category:' + category
      @tempSetAdd categoryKey, rawKey

    RedisService.get key
    .then (value) ->
      if value?
        try
          return JSON.parse value
        catch err
          console.log 'error parsing', key, value
          return null

      fn().then (value) ->
        if (value isnt null and value isnt undefined) or not ignoreNull
          RedisService.set key, JSON.stringify value
          .then ->
            RedisService.expire key, expireSeconds

        return value

  deleteByCategory: (category) =>
    categoryKey = 'category:' + category
    @tempSetGetAll categoryKey
    .then (categoryKeys) =>
      Promise.map categoryKeys, @deleteByKey
    .then =>
      @deleteByKey categoryKey

  deleteByKey: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.del key

module.exports = new CacheService()
