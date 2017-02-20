RedisService = require './redis'
Redlock = require 'redlock'
config = require '../config'

DEFAULT_CACHE_EXPIRE_SECONDS = 3600 * 24 * 30 # 30 days
DEFAULT_LOCK_EXPIRE_SECONDS = 3600 * 24 * 40000 # 100+ years
DEFAULT_REDLOCK_EXPIRE_SECONDS = 30

class CacheService
  KEYS: {}
  LOCK_PREFIXES:
    KUE_PROCESS: 'kue:process'
    BROADCAST: 'broadcast'
  LOCKS: {}
  PREFIXES:
    CHAT_USER: 'chat:user'
    THREAD_USER: 'thread:user1'
    THREAD_DECK: 'thread:deck'
    USER_DATA_CONVERSATION_USERS: 'user_data:conversation_users'
    USER_DATA_FOLLOWERS: 'user_data:followers'
    USER_DATA_FOLLOWING: 'user_data:following'
    USER_DATA_BLOCKED_USERS: 'user_data:blocked_users'
    USER_DATA_CLASH_ROYALE_DECK_IDS: 'user_data:clash_royale_deck_ids'
    CLASH_ROYALE_CARD: 'clash_royale_card7'
    CLASH_ROYALE_CARD_RANK: 'clash_royal_card:rank'
    CLASH_ROYALE_DECK_RANK: 'clash_royal_deck:rank'
    USERNAME_SEARCH: 'username:search'

  constructor: ->
    @redlock = new Redlock [RedisService], {
      driftFactor: 0.01
      retryCount: 0
      # retryDelay:  200
    }

  set: (key, value, {expireSeconds}) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.set key, JSON.stringify value
    .then ->
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
  runOnce: (key, fn, {expireSeconds} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_LOCK_EXPIRE_SECONDS
    # TODO: use redlock
    setVal = '1'
    RedisService.set key, setVal, 'NX', 'EX', expireSeconds
    .then (value) ->
      if value isnt null
        fn()

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

  preferCache: (key, fn, {expireSeconds} = {}) ->
    key = config.REDIS.PREFIX + ':' + key
    expireSeconds ?= DEFAULT_CACHE_EXPIRE_SECONDS

    RedisService.get key
    .then (value) ->
      if value?
        return JSON.parse value

      fn().then (value) ->
        RedisService.set key, JSON.stringify value
        .then ->
          RedisService.expire key, expireSeconds

        return value

  deleteByKey: (key) ->
    key = config.REDIS.PREFIX + ':' + key
    RedisService.del key

module.exports = new CacheService()
