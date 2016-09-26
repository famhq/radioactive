log = require 'loga'
_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'
moment = require 'moment'

config = require '../config'
User = require '../models/user'
UserData = require '../models/user_data'
ChatMessage = require '../models/chat_message'
ThreadMessage = require '../models/thread_message'
CacheService = require './cache'

TYPES =
  USER:
    DATA: 'user:data'
  USER_DATA:
    CONVERSATION_USERS: 'userData:conversationUsers'
    FOLLOWERS: 'userData:followers'
    FOLLOWING: 'userData:following'
    BLOCKED_USERS: 'userData:blockedUsers'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
  CONVERSATION:
    MESSAGES: 'conversation:messages'
  THREAD_MESSAGE:
    USER: 'threadMessage:user'
  THREAD:
    FIRST_MESSAGE: 'thread:firstMessage'
    MESSAGES: 'thread:messages'
    MESSAGE_COUNT: 'thread:messageCount'

TEN_DAYS_SECONDS = 3600 * 24 * 10
ONE_HOUR_SECONDS = 3600
ONE_DAY_SECONDS = 3600 * 24
FIVE_MINUTES_SECONDS = 60 * 5
MAX_FRIENDS = 100 # FIXME add pagination

getUserDataItems = (userData) ->
  key = CacheService.PREFIXES.USER_ITEMS + ':' + userData.userId
  CacheService.preferCache key, ->
    if _.isEmpty userData.itemIds
      Promise.resolve []
    else
      Promise.map userData.itemIds, (itemId) ->
        Promise.props _.defaults {
          item: Item.getById(itemId.id).then Item.sanitize null
        }, itemId
      .filter ({item}) -> Boolean item
  , {expireSeconds: ONE_HOUR_SECONDS}

embedFn = _.curry (embed, object) ->
  embedded = _.cloneDeep object
  unless embedded
    return Promise.resolve null

  embedded.embedded = embed
  _.forEach embed, (key) ->
    switch key
      when TYPES.USER.DATA
        embedded.data = UserData.getByUserId(embedded.id)
                        .then embedFn [TYPES.USER_DATA.CONVERSATION_USERS]

      when TYPES.USER_DATA.CONVERSATION_USERS
        key = CacheService.PREFIXES.USER_DATA_CONVERSATION_USERS +
              ':' + embedded.userId
        embedded.conversationUsers =
          CacheService.preferCache key, ->
            if embedded.conversationUserIds
              Promise.map embedded.conversationUserIds, (userId) ->
                User.getById userId
                .then User.sanitizePublic null
            else Promise.resolve []
          , {expireSeconds: TEN_DAYS_SECONDS}

      when TYPES.USER_DATA.FOLLOWING
        #
        # NOTE: friend's gold, items, etc... will be stale by a day
        #
        key = CacheService.PREFIXES.USER_DATA_FOLLOWING + ':' + embedded.userId
        mmt = moment()
        mmtMidnight = mmt.clone().utcOffset(config.PT_UTC_OFFSET).startOf('day')
        secondsSinceMidnightPt = mmt.clone().utcOffset(config.PT_UTC_OFFSET)
          .diff(mmtMidnight, 'seconds')
        secondsUntilMidnight = ONE_DAY_SECONDS - secondsSinceMidnightPt

        embedded.following = CacheService.preferCache key, ->
          Promise.map(
            _.takeRight(embedded.followingIds, MAX_FRIENDS), (userId) ->
              User.getById userId
          )
          .filter (user) -> Boolean user
          .map (user) ->
            User.sanitizePublic(null, user)
        # CLEARED AT MIDNIGHT FOR GITING DAILY DATA INFO
        , {expireSeconds: secondsUntilMidnight}

      when TYPES.USER_DATA.FOLLOWERS
        key = CacheService.PREFIXES.USER_DATA_FOLLOWERS + ':' + embedded.userId
        embedded.followers = CacheService.preferCache key, ->
          Promise.map(
            _.takeRight(embedded.followerIds, MAX_FRIENDS), (userId) ->
              User.getById userId
          )
          .filter (user) -> Boolean user
          .map (user) ->
            User.sanitizePublic(null, user)
        , {expireSeconds: ONE_DAY_SECONDS}

      when TYPES.USER_DATA.BLOCKED_USERS
        key = CacheService.PREFIXES.USER_BLOCKED_USERS + ':' + embedded.userId
        embedded.blockedUsers = CacheService.preferCache key, ->
          Promise.map(
            _.takeRight(embedded.blockedUserIds, MAX_FRIENDS), (userId) ->
              User.getById userId
          )
          .filter (user) -> Boolean user
          .map (user) ->
            User.sanitizePublic(null, user)
        , {expireSeconds: ONE_DAY_SECONDS}

      when TYPES.CONVERSATION.MESSAGES
        if embedded.userId1 and embedded.userId2
          embedded.messages = ChatMessage.getAllByUserIds {
            userId1: embedded.userId1
            userId2: embedded.userId2
          }

      when TYPES.THREAD.MESSAGES
        embedded.messages = ThreadMessage.getAllByThreadId embedded.id

      when TYPES.THREAD.FIRST_MESSAGE
        embedded.firstMessage = \
          ThreadMessage.getFirstByThreadId embedded.id
          .then embedFn [TYPES.THREAD_MESSAGE.USER]

      when TYPES.THREAD.MESSAGE_COUNT
        unless embedded.messages
          embedded.messages = ThreadMessage.getAllByThreadId embedded.id
        embedded.messageCount = embedded.messages.then (messages) ->
          messages?.length

      when TYPES.THREAD_MESSAGE.USER
        if embedded.userId
          key = CacheService.PREFIXES.THREAD_USER + ':' + embedded.userId
          embedded.user =
            CacheService.preferCache key, ->
              User.getById embedded.userId
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.user = null

      when TYPES.CHAT_MESSAGE.USER
        if embedded.userId
          key = CacheService.PREFIXES.CHAT_USER + ':' + embedded.userId
          embedded.user =
            CacheService.preferCache key, ->
              User.getById embedded.userId
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.user = null

  return Promise.props embedded

class EmbedService
  TYPES: TYPES
  embed: embedFn

module.exports = new EmbedService()
