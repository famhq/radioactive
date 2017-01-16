_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
User = require '../models/user'
UserData = require '../models/user_data'
ChatMessage = require '../models/chat_message'
ThreadMessage = require '../models/thread_message'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
GroupRecord = require '../models/group_record'
GroupUserData = require '../models/group_user_data'
CacheService = require './cache'

TYPES =
  USER:
    DATA: 'user:data'
    IS_ONLINE: 'user:isOnline'
    GROUP_DATA: 'user:groupData'
  USER_DATA:
    CONVERSATION_USERS: 'userData:conversationUsers'
    FOLLOWERS: 'userData:followers'
    FOLLOWING: 'userData:following'
    BLOCKED_USERS: 'userData:blockedUsers'
    CLASH_ROYALE_DECK_IDS: 'userData:clashRoyaleDeckIds'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
  CONVERSATION:
    USERS: 'conversation:users'
    LAST_MESSAGE: 'conversation:lastMessage'
  CLASH_ROYALE_USER_DECK:
    DECK: 'clashRoyaleUserDeck:deck'
  CLASH_ROYALE_DECK:
    CARDS: 'clashRoyaleDeck:cards'
  GROUP:
    USERS: 'group:users'
  GROUP_RECORD_TYPE:
    USER_VALUES: 'groupRecordType:userValues'
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
LAST_ACTIVE_TIME_MS = 60 * 15
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
        .then (userData) ->
          _.defaults {userId: embedded.id}, userData
        .then embedFn [
          TYPES.USER_DATA.CLASH_ROYALE_DECK_IDS
        ]

      when TYPES.USER.GROUP_DATA
        console.log 'embeddddd'
        embedded.groupData = GroupUserData.getByUserIdAndGroupId(
          embedded.id, embedded.groupId
        )

      when TYPES.USER.IS_ONLINE
        embedded.isOnline = moment(embedded.lastActiveTime)
                            .add(LAST_ACTIVE_TIME_MS)
                            .isAfter moment()

      when TYPES.USER_DATA.CLASH_ROYALE_DECK_IDS
        key = CacheService.PREFIXES.USER_DATA_CLASH_ROYALE_DECK_IDS +
              ':' + embedded.userId
        embedded.clashRoyaleDeckIds =
          CacheService.preferCache key, ->
            if embedded.userId
              ClashRoyaleUserDeck.getAllFavoritedByUserId embedded.userId
              .map (deck) -> deck?.deckId
            else
              Promise.resolve null
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

      when TYPES.GROUP_RECORD_TYPE.USER_VALUES
        embedded.userValues = GroupRecord.getAllRecordsByTypeAndTime {
          groupRecordTypeId: embedded.id
          scaledTime: GroupRecord.getScaledTimeByTimeScale embedded.timeScale
        }

      when TYPES.CONVERSATION.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId

      when TYPES.GROUP.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId
        .map embedFn [TYPES.USER.IS_ONLINE]

      when TYPES.CONVERSATION.LAST_MESSAGE
        embedded.lastMessage = \
          ChatMessage.getLastByConversationId embedded.id

      when TYPES.THREAD.MESSAGES
        embedded.messages = ThreadMessage.getAllByThreadId embedded.id
        .map embedFn [TYPES.THREAD_MESSAGE.USER]

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

      when TYPES.CLASH_ROYALE_DECK.CARDS
        embedded.cards = Promise.map embedded.cardIds, (cardId) ->
          key = CacheService.PREFIXES.CLASH_ROYALE_CARD + ':' + cardId
          CacheService.preferCache key, ->
            ClashRoyaleCard.getById cardId
            .then ClashRoyaleCard.sanitize(null)
          , {expireSeconds: FIVE_MINUTES_SECONDS}
        embedded.averageElixirCost = embedded.cards.then (cards) ->
          mean = _.meanBy cards, (card) ->
            card.data?.elixirCost
          Math.round(mean * 10) / 10

      when TYPES.CLASH_ROYALE_USER_DECK.DECK
        embedded.deck = ClashRoyaleDeck.getById embedded.deckId
        .then embedFn [TYPES.CLASH_ROYALE_DECK.CARDS]

  return Promise.props embedded

class EmbedService
  TYPES: TYPES
  embed: embedFn

module.exports = new EmbedService()
