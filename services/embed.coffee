_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
User = require '../models/user'
UserData = require '../models/user_data'
Conversation = require '../models/conversation'
ChatMessage = require '../models/chat_message'
ThreadComment = require '../models/thread_comment'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
Deck = require '../models/clash_royale_deck'
Group = require '../models/group'
GroupRecord = require '../models/group_record'
GameRecord = require '../models/game_record'
UserGroupData = require '../models/user_group_data'
Player = require '../models/player'
chestCycle = require '../resources/data/chest_cycle'
CacheService = require './cache'

doubleCycle = chestCycle.concat chestCycle

TYPES =
  USER:
    DATA: 'user:data'
    IS_ONLINE: 'user:isOnline'
    GROUP_DATA: 'user:groupData'
    GAME_DATA: 'user:gameData'
  USER_DATA:
    CONVERSATION_USERS: 'userData:conversationUsers'
    FOLLOWERS: 'userData:followers'
    FOLLOWING: 'userData:following'
    BLOCKED_USERS: 'userData:blockedUsers'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
  CONVERSATION:
    USERS: 'conversation:users'
    LAST_MESSAGE: 'conversation:lastMessage'
  CLAN:
    PLAYERS: 'clan:players'
    IS_UPDATABLE: 'clan:isUpdatable'
  CLASH_ROYALE_USER_DECK:
    DECK: 'clashRoyaleUserDeck:deck'
  CLASH_ROYALE_DECK:
    CARDS: 'clashRoyaleDeck:cards'
  EVENT:
    USERS: 'event:users'
    CREATOR: 'event:creator'
  GROUP:
    USERS: 'group:users'
    CONVERSATIONS: 'group:conversations'
  GROUP_RECORD_TYPE:
    USER_VALUES: 'groupRecordType:userValues'
  GAME_RECORD_TYPE:
    ME_VALUES: 'gameRecordType:userValues'
  PLAYER:
    CHEST_CYCLE: 'player:chestCycle'
    IS_UPDATABLE: 'player:isUpdatable'
    VERIFIED_USER: 'player:verifiedUser'
  THREAD_COMMENT:
    CREATOR: 'threadComment:creator'
  THREAD:
    CREATOR: 'thread:creator'
    COMMENT_COUNT: 'thread:commentCount'
    SCORE: 'thread:score'
    DECK: 'thread:deck'

TEN_DAYS_SECONDS = 3600 * 24 * 10
ONE_HOUR_SECONDS = 3600
ONE_DAY_SECONDS = 3600 * 24
FIVE_MINUTES_SECONDS = 60 * 5
LAST_ACTIVE_TIME_MS = 60 * 15
MAX_FRIENDS = 100 # FIXME add pagination
NEWBIE_CHEST_COUNT = 6
CHEST_COUNT = 30
MIN_TIME_UNTIL_NEXT_UPDATE_MS = 3600 * 1000 # 1hr

# separate service so models don't have to depend on
# each other (circular). eg user data needing user for
# embedding followers, and user needing user data

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

embedFn = _.curry ({embed, user, groupId, gameId}, object) ->
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

      when TYPES.USER.GROUP_DATA
        embedded.groupData = UserGroupData.getByUserIdAndGroupId(
          embedded.id, groupId
        )

      when TYPES.USER.GAME_DATA
        embedded.gameData = Player.getByUserIdAndGameId(
          embedded.id, gameId
        )

      when TYPES.USER.IS_ONLINE
        embedded.isOnline = moment(embedded.lastActiveTime)
                            .add(LAST_ACTIVE_TIME_MS)
                            .isAfter moment()

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

      when TYPES.GAME_RECORD_TYPE.ME_VALUES
        minScaledTime = GameRecord.getScaledTimeByTimeScale(
          'minute', moment().subtract(30, 'day')
        )
        maxScaledTime = GameRecord.getScaledTimeByTimeScale 'minute'

        embedded.userValues = GameRecord.getRecords {
          gameRecordTypeId: embedded.id
          userId: user.id
          minScaledTime: minScaledTime
          maxScaledTime: maxScaledTime
          limit: 50
        }

      when TYPES.CLAN.PLAYERS
        embedded.players = Promise.map embedded.players, (player) ->
          Player.getByPlayerIdAndGameId player.playerId, embedded.gameId
          .then embedFn {embed: [TYPES.PLAYER.VERIFIED_USER]}
          .then (playerObj) ->
            _.defaults {player: playerObj}, player

      when TYPES.CLAN.IS_UPDATABLE
        msSinceUpdate = new Date() - new Date(embedded.lastQueuedTime)
        embedded.isUpdatable = not embedded.lastQueuedTime or
                                msSinceUpdate >= MIN_TIME_UNTIL_NEXT_UPDATE_MS

      when TYPES.CONVERSATION.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId
        .map User.sanitizePublic null

      when TYPES.EVENT.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId
        .map User.sanitizePublic null

      when TYPES.EVENT.CREATOR
        embedded.creator = User.getById embedded.creatorId

      when TYPES.GROUP.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId
        .map embedFn {embed: [TYPES.USER.IS_ONLINE]}
        .map User.sanitizePublic null

      when TYPES.GROUP.CONVERSATIONS
        embedded.conversations = Conversation.getAllByGroupId embedded.id

      when TYPES.GROUP.USER_CONVERSATIONS
        embedded.conversations = Conversation.getAllByGroupId embedded.id
        .filter (conversation) ->
          Group.hasPermission embedded, user, {level: ''} # FIXME

      when TYPES.CONVERSATION.LAST_MESSAGE
        embedded.lastMessage = \
          ChatMessage.getLastByConversationId embedded.id

      when TYPES.THREAD.COMMENTS
        embedded.comments = ThreadComment.getAllByThreadId embedded.id
        .map embedFn {embed: [TYPES.THREAD_COMMENT.USER]}

      when TYPES.THREAD.COMMENT_COUNT
        if embedded.comments
          comments = embedded.comments
        else
          comments = ThreadComment.getAllByThreadId embedded.id
        embedded.commentCount = comments.then (comments) ->
          comments?.length

      when TYPES.THREAD.SCORE
        embedded.score = embedded.upvotes - embedded.downvotes

      when TYPES.THREAD.DECK
        key = CacheService.PREFIXES.THREAD_DECK + ':' + embedded.id
        embedded.deck = CacheService.preferCache key, ->
          Deck.getById embedded.data.deckId
          .then embedFn {embed: [TYPES.CLASH_ROYALE_DECK.CARDS]}
        , {expireSeconds: ONE_DAY_SECONDS}

      when TYPES.THREAD.CREATOR
        if embedded.creatorId
          key = CacheService.PREFIXES.THREAD_CREATOR + ':' + embedded.creatorId
          embedded.creator =
            CacheService.preferCache key, ->
              User.getById embedded.creatorId
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.creator = null

      when TYPES.THREAD_COMMENT.CREATOR
        if embedded.creatorId
          key = CacheService.PREFIXES.THREAD_CREATOR + ':' + embedded.creatorId
          embedded.creator =
            CacheService.preferCache key, ->
              User.getById embedded.creatorId
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.creator = null

      when TYPES.CHAT_MESSAGE.USER
        if embedded.userId
          key = CacheService.PREFIXES.CHAT_USER + ':' + embedded.userId
          embedded.user =
            CacheService.preferCache key, ->
              console.log 'get chat user / player data'
              User.getById embedded.userId
              .then embedFn {
                embed: [TYPES.USER.GAME_DATA], gameId: config.CLASH_ROYALE_ID
              }
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.user = null

      when TYPES.PLAYER.CHEST_CYCLE
        if embedded.data?.chestCycle
          startingPos = embedded.data.chestCycle.pos
          pos = (startingPos - NEWBIE_CHEST_COUNT) % chestCycle.length
          chests = doubleCycle.slice pos, pos + CHEST_COUNT
          embedded.data.chestCycle?.chests = chests
          embedded.data.chestCycle?.countUntil = {
            superMagical: embedded.data.chestCycle.superMagicalPos - startingPos
            epic: embedded.data.chestCycle.epicPos - startingPos
            legendary: embedded.data.chestCycle.legendaryPos - startingPos
          }

      when TYPES.PLAYER.IS_UPDATABLE
        msSinceUpdate = new Date() - new Date(embedded.lastQueuedTime)
        embedded.isUpdatable = not embedded.lastQueuedTime or
                                msSinceUpdate >= MIN_TIME_UNTIL_NEXT_UPDATE_MS

      when TYPES.PLAYER.VERIFIED_USER
        if embedded.verifiedUserId
          prefix = CacheService.PREFIXES.PLAYER_VERIFIED_USER
          key = prefix + ':' + embedded.verifiedUserId
          embedded.verifiedUser =
            CacheService.preferCache key, ->
              User.getById embedded.verifiedUserId
              .then User.sanitizePublic(null)
            , {expireSeconds: ONE_HOUR_SECONDS}
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
          count = cards.length
          sum = _.sumBy cards, (card) ->
            if _.isNumber card.data?.cost
              card.data?.cost
            else
              # mirror
              count -= 1
              0
          mean = sum / count
          Math.round(mean * 10) / 10

      when TYPES.CLASH_ROYALE_USER_DECK.DECK
        prefix = CacheService.PREFIXES.CLASH_ROYALE_USER_DECK_DECK
        key = "#{prefix}:#{embedded.id}"
        embedded.deck = CacheService.preferCache key, ->
          ClashRoyaleDeck.getById embedded.deckId
          .then embedFn {embed: [TYPES.CLASH_ROYALE_DECK.CARDS]}
        , {expireSeconds: ONE_DAY_SECONDS}

      else
        console.log 'no match found', key

  return Promise.props embedded

class EmbedService
  TYPES: TYPES
  embed: embedFn

module.exports = new EmbedService()
