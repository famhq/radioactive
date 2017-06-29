_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
User = require '../models/user'
UserData = require '../models/user_data'
Ban = require '../models/ban'
Conversation = require '../models/conversation'
ChatMessage = require '../models/chat_message'
ThreadComment = require '../models/thread_comment'
ThreadVote = require '../models/thread_vote'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleMatch = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'
Group = require '../models/group'
Star = require '../models/star'
ClanRecord = require '../models/clan_record'
GroupRecord = require '../models/group_record'
UserRecord = require '../models/user_record'
UserGroupData = require '../models/user_group_data'
Player = require '../models/player'
UserPlayer = require '../models/user_player'
UserFollower = require '../models/user_follower'
chestCycle = require '../resources/data/chest_cycle'
CacheService = require './cache'
TagConverterService = require './tag_converter'

doubleCycle = chestCycle.concat chestCycle

TYPES =
  BAN:
    USER: 'ban:user'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
  CONVERSATION:
    USERS: 'conversation:users'
    LAST_MESSAGE: 'conversation:lastMessage'
  CLAN:
    PLAYERS: 'clan:players'
    IS_UPDATABLE: 'clan:isUpdatable'
    GROUP: 'clan:group'
  CLASH_ROYALE_USER_DECK:
    DECK: 'clashRoyaleUserDeck:deck1'
  CLASH_ROYALE_MATCH:
    DECK: 'clashRoyaleMatch:deck1'
  CLASH_ROYALE_DECK:
    CARDS: 'clashRoyaleDeck:cards'
  EVENT:
    USERS: 'event:users'
    CREATOR: 'event:creator'
  STAR:
    USER: 'star:user'
    GROUP: 'star:group'
  GROUP:
    USERS: 'group:users'
    CONVERSATIONS: 'group:conversations'
    STAR: 'group:star'
  CLAN_RECORD_TYPE:
    CLAN_VALUES: 'clanRecordType:clanValues'
  GROUP_RECORD_TYPE:
    USER_VALUES: 'groupRecordType:userValues'
  GAME_RECORD_TYPE:
    ME_VALUES: 'gameRecordType:userValues'
  PLAYER:
    CHEST_CYCLE: 'player:chestCycle'
    IS_UPDATABLE: 'player:isUpdatable'
    VERIFIED_USER: 'player:verifiedUser'
    HI: 'player:hi'
    USER_IDS: 'player:user_ids'
  THREAD_COMMENT:
    CREATOR: 'threadComment:creator'
  THREAD:
    CREATOR: 'thread:creator'
    COMMENT_COUNT: 'thread:commentCount'
    MY_VOTE: 'thread:myVote'
    DECK: 'thread:deck'
  USER:
    DATA: 'user:data'
    IS_ONLINE: 'user:isOnline'
    FOLLOWER_COUNT: 'user:followerCount'
    GROUP_DATA: 'user:groupData'
    GAME_DATA: 'user:gameData'
    IS_BANNED: 'user:isBanned'
  USER_DATA:
    CONVERSATION_USERS: 'userData:conversationUsers'
    FOLLOWERS: 'userData:followers'
    FOLLOWING: 'userData:following'
    BLOCKED_USERS: 'userData:blockedUsers'

TEN_DAYS_SECONDS = 3600 * 24 * 10
ONE_HOUR_SECONDS = 3600
ONE_DAY_SECONDS = 3600 * 24
FIVE_MINUTES_SECONDS = 60 * 5
LAST_ACTIVE_TIME_MS = 60 * 15
MAX_FRIENDS = 100 # FIXME add pagination
NEWBIE_CHEST_COUNT = 0
CHEST_COUNT = 300
MIN_TIME_UNTIL_NEXT_UPDATE_MS = 3600 * 1000 # 1hr

profileDialogUserEmbed = [TYPES.USER.GAME_DATA, TYPES.USER.IS_BANNED]

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

embedFn = _.curry ({embed, user, clanId, groupId, gameId, userId}, object) ->
  embedded = _.cloneDeep object
  unless embedded
    return Promise.resolve null

  embedded.embedded = embed
  _.forEach embed, (key) ->
    switch key
      when TYPES.USER.DATA
        embedded.data = UserData.getByUserId(embedded.id, {preferCache: true})
        .then (userData) ->
          _.defaults {userId: embedded.id}, userData

      when TYPES.USER.FOLLOWER_COUNT
        key = CacheService.PREFIXES.USER_FOLLOWER_COUNT + ':' + embedded.id
        embedded.followerCount = CacheService.preferCache key, ->
          UserFollower.getCountByFollowingId embedded.id
        , {expireSeconds: FIVE_MINUTES_SECONDS}

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

      when TYPES.USER.IS_BANNED
        embedded.isChatBanned = Ban.getByUserId embedded.id, {
          scope: 'chat'
          preferCache: true
        }
        .then (ban) ->
          console.log ban
          Boolean ban?.userId

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

      # TODO: can probably consolidate a lot of clan/userRecords stuff
      when TYPES.CLAN_RECORD_TYPE.CLAN_VALUES
        if embedded.timeScale is 'days'
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'day', moment().subtract(30, 'day')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'day'
        else if embedded.timeScale is 'weeks'
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'week', moment().subtract(30, 'week')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'week'
        else
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'minute', moment().subtract(30, 'day')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'minute'

        embedded.clanValues = ClanRecord.getRecords {
          clanRecordTypeId: embedded.id
          clanId: clanId
          minScaledTime: minScaledTime
          maxScaledTime: maxScaledTime
          limit: 50
        }

      when TYPES.GAME_RECORD_TYPE.ME_VALUES
        if embedded.timeScale is 'days'
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'day', moment().subtract(30, 'day')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'day'
        else if embedded.timeScale is 'weeks'
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'week', moment().subtract(30, 'week')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'week'
        else
          minScaledTime = UserRecord.getScaledTimeByTimeScale(
            'minute', moment().subtract(30, 'day')
          )
          maxScaledTime = UserRecord.getScaledTimeByTimeScale 'minute'

        embedded.userValues = UserRecord.getRecords {
          gameRecordTypeId: embedded.id
          userId: userId
          minScaledTime: minScaledTime
          maxScaledTime: maxScaledTime
          limit: 50
        }

      when TYPES.CLAN.PLAYERS
        if embedded.players
          embedded.players = Promise.map embedded.players, (player) ->
            Player.getByPlayerIdAndGameId player.playerId, embedded.gameId
            .then embedFn {
              embed: [TYPES.PLAYER.VERIFIED_USER], gameId: embedded.gameId
            }
            .then (playerObj) ->
              _.defaults {player: playerObj}, player


      when TYPES.CLAN.GROUP
        if embedded.groupId
          embedded.group = Group.getById(embedded.groupId)
                            .then Group.sanitizePublic null

      when TYPES.CLAN.IS_UPDATABLE
        msSinceUpdate = new Date() - new Date(embedded.lastQueuedTime)
        embedded.isUpdatable = Promise.resolve(not embedded.lastQueuedTime or
                                msSinceUpdate >= MIN_TIME_UNTIL_NEXT_UPDATE_MS)

      when TYPES.STAR.USER
        embedded.user = User.getById embedded.userId
        .then embedFn {
          embed: profileDialogUserEmbed.concat [TYPES.USER.FOLLOWER_COUNT]
          gameId: config.CLASH_ROYALE_ID
        }
        .then User.sanitizePublic null

      when TYPES.STAR.GROUP
        embedded.group = Group.getById embedded.groupId
        .then Group.sanitizePublic null

      when TYPES.BAN.USER
        embedded.user = User.getById embedded.userId
        .then embedFn {
          embed: profileDialogUserEmbed, gameId: config.CLASH_ROYALE_ID
        }
        .then User.sanitizePublic null

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

      when TYPES.GROUP.STAR
        if embedded.starId
          key = CacheService.PREFIXES.GROUP_STAR + ':' + embedded.id
          embedded.star = CacheService.preferCache key, ->
            Star.getById embedded.starId
            .then embedFn {embed: [TYPES.STAR.USER]}
          , {expireSeconds: ONE_HOUR_SECONDS}

      when TYPES.GROUP.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId
        .map embedFn {embed: [TYPES.USER.IS_ONLINE]}
        .map User.sanitizePublic null

      when TYPES.GROUP.CONVERSATIONS
        embedded.conversations = Conversation.getAllByGroupId embedded.id

      when TYPES.CONVERSATION.LAST_MESSAGE
        embedded.lastMessage = \
          ChatMessage.getLastByConversationId embedded.id

      when TYPES.THREAD.COMMENTS
        embedded.comments = ThreadComment.getAllByParentIdAndParentType(
          embedded.id, 'thread'
        ).map embedFn {embed: [TYPES.THREAD_COMMENT.USER]}

      when TYPES.THREAD.COMMENT_COUNT
        if embedded.comments
          comments = embedded.comments
        else
          comments = ThreadComment.getAllByParentIdAndParentType(
            embedded.id, 'thread'
          )
        embedded.commentCount = comments.then (comments) ->
          comments?.length

      when TYPES.THREAD.MY_VOTE
        if userId
          embedded.myVote = ThreadVote.getByCreatorIdAndParent(
            userId
            embedded.id
            'thread'
          )

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
                embed: profileDialogUserEmbed, gameId: config.CLASH_ROYALE_ID
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
            giant: if (i = chests.indexOf('giant')) isnt -1 then i + 1 else null
            magical: if (i = chests.indexOf('magic')) isnt -1 then i + 1 else null
            superMagical: embedded.data.chestCycle.superMagicalPos - startingPos
            epic: embedded.data.chestCycle.epicPos - startingPos
            legendary: embedded.data.chestCycle.legendaryPos - startingPos
          }

      when TYPES.PLAYER.IS_UPDATABLE
        msSinceUpdate = new Date() - new Date(embedded.lastQueuedTime)
        embedded.isUpdatable = Promise.resolve(not embedded.lastQueuedTime or
                                msSinceUpdate >= MIN_TIME_UNTIL_NEXT_UPDATE_MS)

      when TYPES.PLAYER.HI
        embedded.hi = Promise.resolve(
          TagConverterService.getHiLoFromTag(embedded.id)?.hi
        )

      when TYPES.PLAYER.VERIFIED_USER
        prefix = CacheService.PREFIXES.PLAYER_VERIFIED_USER
        key = prefix + ':' + embedded.id
        embedded.verifiedUser =
          CacheService.preferCache key, ->
            UserPlayer.getVerifiedByPlayerIdAndGameId embedded.id, gameId
            .then (userPlayer) ->
              if userPlayer?.userId
                User.getById userPlayer.userId
                .then User.sanitizePublic(null)
              else
                null
          , {expireSeconds: ONE_HOUR_SECONDS}

      when TYPES.PLAYER.USER_IDS
        prefix = CacheService.PREFIXES.PLAYER_USER_IDS
        key = prefix + ':' + embedded.id
        embedded.userIds =
          CacheService.preferCache key, ->
            UserPlayer.getAllByPlayerIdAndGameId embedded.id, gameId
            .map ({userId}) -> userId
          , {expireSeconds: ONE_DAY_SECONDS, ignoreNull: true}

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
