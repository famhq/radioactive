_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
User = require '../models/user'
UserData = require '../models/user_data'
AddonVote = require '../models/addon_vote'
Ban = require '../models/ban'
Conversation = require '../models/conversation'
ChatMessage = require '../models/chat_message'
ThreadComment = require '../models/thread_comment'
ThreadVote = require '../models/thread_vote'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleMatch = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'
Group = require '../models/group'
Star = require '../models/star'
ClashRoyaleClanRecord = require '../models/clash_royale_clan_record'
GroupRecord = require '../models/group_record'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
UserGroupData = require '../models/user_group_data'
Player = require '../models/player'
UserPlayer = require '../models/user_player'
UserFollower = require '../models/user_follower'
CacheService = require './cache'
TagConverterService = require './tag_converter'

TYPES =
  ADDON:
    MY_VOTE: 'addon:myVote'
  BAN:
    USER: 'ban:user'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
  CONVERSATION:
    USERS: 'conversation:users'
    LAST_MESSAGE: 'conversation:lastMessage'
  CLAN:
    PLAYERS: 'clan:players'
    GROUP: 'clan:group'
  CLASH_ROYALE_PLAYER_DECK:
    DECK: 'clashRoyalePlayerDeck:deck1'
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
    USER_IDS: 'group:userIds'
    USERS: 'group:users'
    CONVERSATIONS: 'group:conversations'
    STAR: 'group:star'
  CLAN_RECORD_TYPE:
    CLAN_VALUES: 'clanRecordType:clanValues'
  GROUP_RECORD_TYPE:
    USER_VALUES: 'groupRecordType:userValues'
  GAME_RECORD_TYPE:
    ME_VALUES: 'gameRecordType:playerValues'
  PLAYER:
    VERIFIED_USER: 'player:verifiedUser'
    HI: 'player:hi'
    COUNTERS: 'player:counters'
    USER_IDS: 'player:user_ids'
  THREAD_COMMENT:
    CREATOR: 'threadComment:creator'
  THREAD:
    CREATOR: 'thread:creator'
    COMMENT_COUNT: 'thread:commentCount'
    PLAYER_DECK: 'thread:playerDeck'
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

embedFn = _.curry (props, object) ->
  {embed, user, clanId, groupId, gameId, userId, playerId} = props
  embedded = _.cloneDeep object
  unless embedded
    return Promise.resolve null

  embedded.embedded = embed
  _.forEach embed, (key) ->
    switch key
      when TYPES.ADDON.MY_VOTE
        embedded.myVote = AddonVote.getByCreatorIdAndAddonId(
          user.id, embedded.id
        )
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
              User.getById userId, {preferCache: true}
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
              User.getById userId, {preferCache: true}
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
              User.getById userId, {preferCache: true}
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
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'day', moment().subtract(30, 'day')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'day'
        else if embedded.timeScale is 'weeks'
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'week', moment().subtract(30, 'week')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'week'
          )
        else
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'minute', moment().subtract(30, 'day')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'minute'
          )

        embedded.clanValues = ClashRoyaleClanRecord.getRecords {
          clanRecordTypeId: embedded.id
          clanId: clanId
          minScaledTime: minScaledTime
          maxScaledTime: maxScaledTime
          limit: 50
        }

      when TYPES.GAME_RECORD_TYPE.ME_VALUES
        if embedded.timeScale is 'days'
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'day', moment().subtract(30, 'day')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'day'
          )
        else if embedded.timeScale is 'weeks'
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'week', moment().subtract(30, 'week')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'week'
          )
        else
          minScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'minute', moment().subtract(30, 'day')
          )
          maxScaledTime = ClashRoyalePlayerRecord.getScaledTimeByTimeScale(
            'minute'
          )

        embedded.playerValues = ClashRoyalePlayerRecord.getRecords {
          gameRecordTypeId: embedded.id
          playerId: playerId
          minScaledTime: minScaledTime
          maxScaledTime: maxScaledTime
          limit: 50
        }

      when TYPES.CLAN.PLAYERS
        if embedded.data.memberList
          key = CacheService.PREFIXES.CLAN_PLAYERS + ':' + embedded.id
          embedded.players = CacheService.preferCache key, ->
            Promise.map embedded.data.memberList, (player) ->
              playerId = player.tag.replace('#', '')
              Player.getByPlayerIdAndGameId playerId, embedded.gameId
              .then embedFn {
                embed: [TYPES.PLAYER.VERIFIED_USER], gameId: embedded.gameId
              }
              .then (playerObj) ->
                playerObj = _.omit playerObj, ['data']
                _.defaults {player: playerObj}, player
          , {expireSeconds: ONE_DAY_SECONDS}

      when TYPES.CLAN.GROUP
        if embedded.groupId
          embedded.group = Group.getById(embedded.groupId)
                            .then Group.sanitizePublic null

      when TYPES.STAR.USER
        embedded.user = User.getById embedded.userId, {preferCache: true}
        .then embedFn {
          embed: profileDialogUserEmbed.concat [TYPES.USER.FOLLOWER_COUNT]
          gameId: config.CLASH_ROYALE_ID
        }
        .then User.sanitizePublic null

      when TYPES.STAR.GROUP
        embedded.group = Group.getById embedded.groupId
        .then Group.sanitizePublic null

      when TYPES.BAN.USER
        embedded.user = User.getById embedded.userId, {preferCache: true}
        .then embedFn {
          embed: profileDialogUserEmbed, gameId: config.CLASH_ROYALE_ID
        }
        .then User.sanitizePublic null

      when TYPES.CONVERSATION.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId, {preferCache: true}
        .map User.sanitizePublic null

      when TYPES.EVENT.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId, {preferCache: true}
        .map User.sanitizePublic null

      when TYPES.EVENT.CREATOR
        embedded.creator = User.getById embedded.creatorId, {preferCache: true}
        .then User.sanitizePublic null

      when TYPES.GROUP.STAR
        if embedded.starId
          key = CacheService.PREFIXES.GROUP_STAR + ':' + embedded.id
          embedded.star = CacheService.preferCache key, ->
            Star.getById embedded.starId
            .then embedFn {embed: [TYPES.STAR.USER]}
          , {expireSeconds: ONE_HOUR_SECONDS}

      when TYPES.GROUP.USER_IDS
        # TODO: cache
        embedded.userIds =
          GroupUser.getAllByGroupId embedded.id
          .map ({userId}) -> userId

      when TYPES.GROUP.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId, {preferCache: true}
        .map embedFn {embed: [TYPES.USER.IS_ONLINE]}
        .map User.sanitizePublic null

      when TYPES.GROUP.CONVERSATIONS
        embedded.conversations = Conversation.getAllByGroupId embedded.id

      when TYPES.CONVERSATION.LAST_MESSAGE
        embedded.lastMessage = \
          ChatMessage.getLastByConversationId embedded.id

      when TYPES.THREAD.COMMENTS
        key = CacheService.PREFIXES.THREAD_COMMENTS + ':' + embedded.id
        embedded.comments = CacheService.preferCache key, ->
          ThreadComment.getAllByParentIdAndParentType(
            embedded.id, 'thread'
          ).map embedFn {embed: [TYPES.THREAD_COMMENT.USER]}
        , {expireSeconds: FIVE_MINUTES_SECONDS}

      when TYPES.THREAD.COMMENT_COUNT
        key = CacheService.PREFIXES.THREAD_COMMENT_COUNT + ':' + embedded.id
        embedded.commentCount = CacheService.preferCache key, ->
          ThreadComment.getCountByParentIdAndParentType(
            embedded.id, 'thread'
          )
        , {expireSeconds: FIVE_MINUTES_SECONDS}

      when TYPES.THREAD.PLAYER_DECK
        key = CacheService.PREFIXES.THREAD_DECK + ':' + embedded.id
        embedded.playerDeck = CacheService.preferCache key, ->
          ClashRoyalePlayerDeck.getByDeckIdAndPlayerId(
            embedded.data.deckId
            embedded.data.playerId
          )
          .then embedFn {embed: [TYPES.CLASH_ROYALE_PLAYER_DECK.DECK]}
          .then (playerDeck) ->
            playerDeck = _.pick playerDeck, [
              'deck', 'wins', 'losses', 'draws', 'gameType', 'playerId', 'deck'
            ]
            playerDeck.deck = _.pick playerDeck.deck, [
              'wins', 'losses', 'draws', 'cards'
            ]
            playerDeck.deck.cards = _.map playerDeck.deck.cards, (card) ->
              _.pick card, ['name', 'key']
            playerDeck
        , {expireSeconds: ONE_DAY_SECONDS}

      when TYPES.THREAD.CREATOR
        if embedded.creatorId
          key = CacheService.PREFIXES.THREAD_CREATOR + ':' + embedded.creatorId
          embedded.creator =
            CacheService.preferCache key, ->
              User.getById embedded.creatorId, {preferCache: true}
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.creator = null

      when TYPES.THREAD_COMMENT.CREATOR
        if embedded.creatorId
          key = CacheService.PREFIXES.THREAD_CREATOR + ':' + embedded.creatorId
          embedded.creator =
            CacheService.preferCache key, ->
              User.getById embedded.creatorId, {preferCache: true}
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
              User.getById embedded.userId, {preferCache: true}
              .then embedFn {
                embed: profileDialogUserEmbed, gameId: config.CLASH_ROYALE_ID
              }
              .then User.sanitizePublic(null)
            , {expireSeconds: FIVE_MINUTES_SECONDS}
        else
          embedded.user = null

      when TYPES.PLAYER.HI
        embedded.hi = Promise.resolve(
          TagConverterService.getHiLoFromTag(embedded.id)?.hi
        )

      when TYPES.PLAYER.COUNTERS
        embedded.counters = Player.getCountersByPlayerIdAndScaledTimeAndGameId(
          embedded.id
          'all'
          config.CLASH_ROYALE_ID
        )

      when TYPES.PLAYER.VERIFIED_USER
        prefix = CacheService.PREFIXES.PLAYER_VERIFIED_USER
        key = prefix + ':' + embedded.id
        embedded.verifiedUser =
          CacheService.preferCache key, ->
            UserPlayer.getVerifiedByPlayerIdAndGameId embedded.id, gameId
            .then (userPlayer) ->
              if userPlayer?.userId
                User.getById userPlayer.userId, {preferCache: true}
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
        cardKeys = embedded.deckId.split('|')
        embedded.cards = Promise.map cardKeys, (cardKey) ->
          key = CacheService.PREFIXES.CLASH_ROYALE_CARD + ':' + cardKey
          CacheService.preferCache key, ->
            (if cardKey
              ClashRoyaleCard.getByKey cardKey
            else
              console.log 'missing cardKey', embedded
              Promise.resolve {})
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

      when TYPES.CLASH_ROYALE_PLAYER_DECK.DECK
        prefix = CacheService.PREFIXES.CLASH_ROYALE_PLAYER_DECK_DECK
        key = "#{prefix}:#{embedded.deckId}"
        embedded.deck = CacheService.preferCache key, ->
          ClashRoyaleDeck.getById embedded.deckId
          .then embedFn {embed: [TYPES.CLASH_ROYALE_DECK.CARDS]}
          .then ClashRoyaleDeck.sanitize null
        , {expireSeconds: ONE_DAY_SECONDS}

      else
        console.log 'no match found', key

  return Promise.props embedded

class EmbedService
  TYPES: TYPES
  embed: embedFn

module.exports = new EmbedService()
