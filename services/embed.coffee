_ = require 'lodash'
Promise = require 'bluebird'
moment = require 'moment'

config = require '../config'
cknex = require '../services/cknex'
User = require '../models/user'
UserData = require '../models/user_data'
UserUpgrade = require '../models/user_upgrade'
AddonVote = require '../models/addon_vote'
Ban = require '../models/ban'
Conversation = require '../models/conversation'
ChatMessage = require '../models/chat_message'
Clan = require '../models/clan'
ThreadComment = require '../models/thread_comment'
ThreadVote = require '../models/thread_vote'
ClashRoyaleCard = require '../models/clash_royale_card'
ClashRoyaleDeck = require '../models/clash_royale_deck'
ClashRoyaleMatch = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'
Group = require '../models/group'
GroupRole = require '../models/group_role'
GroupUser = require '../models/group_user'
Item = require '../models/item'
Star = require '../models/star'
ClashRoyaleClanRecord = require '../models/clash_royale_clan_record'
GroupRecord = require '../models/group_record'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
ClashRoyalePlayerDeck = require '../models/clash_royale_player_deck'
SpecialOffer = require '../models/special_offer'
Player = require '../models/player'
Trade = require '../models/trade'
UserPlayer = require '../models/user_player'
UserFollower = require '../models/user_follower'
CacheService = require './cache'
TagConverterService = require './tag_converter'
cardIds = require '../resources/data/card_ids.json'

TYPES =
  ADDON:
    MY_VOTE: 'addon:myVote'
  BAN:
    USER: 'ban:user'
  CLASH_ROYALE_CARD:
    STATS: 'clashRoyaleCard:stats'
    POPULAR_DECKS: 'clashRoyaleCard:popularDecks'
    BEST_DECKS: 'clashRoyaleCard:bestDecks'
  CHAT_MESSAGE:
    USER: 'chatMessage:user'
    MENTIONED_USERS: 'chatMessage:mentionedUsers'
    GROUP_USER: 'chatMessage:groupUser'
    TIME: 'chatMessage:time'
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
    STATS: 'clashRoyaleDeck:stats'
    COPY_URL: 'clashRoyaleDeck:copyUrl'
  EVENT:
    USERS: 'event:users'
    CREATOR: 'event:creator'
  STAR:
    USER: 'star:user'
    GROUP: 'star:group'
  GROUP:
    USER_IDS: 'group:userIds'
    USER_COUNT: 'group:userCount'
    USERS: 'group:users'
    ME_GROUP_USER: 'group:group_user'
    CONVERSATIONS: 'group:conversations'
    STAR: 'group:star'
  GROUP_AUDIT_LOG:
    USER: 'groupAuditLog:user'
    TIME: 'groupAuditLog:time'
  GROUP_USER:
    ROLES: 'groupUser:roles'
    ROLE_NAMES: 'groupUser:roleNames'
    XP: 'groupUser:xp'
    USER: 'groupUser:user'
  CLAN_RECORD_TYPE:
    CLAN_VALUES: 'clanRecordType:clanValues'
  GROUP_RECORD_TYPE:
    USER_VALUES: 'groupRecordType:userValues'
  GAME_RECORD_TYPE:
    ME_VALUES: 'gameRecordType:playerValues'
  SPECIAL_OFFER:
    TRANSACTION: 'specialOffer:transaction'
  SPECIAL_OFFER_TRANSACTION:
    SPECIAL_OFFER: 'specialOfferTransaction:specialOffer'
  PLAYER:
    VERIFIED_USER: 'player:verifiedUser'
    HI: 'player:hi'
    COUNTERS: 'player:counters'
    USER_IDS: 'player:user_ids'
  THREAD_COMMENT:
    CREATOR: 'threadComment:creator'
    GROUP_USER: 'threadComment:groupUser'
    TIME: 'threadComment:time'
  THREAD:
    CREATOR: 'thread:creator'
    COMMENT_COUNT: 'thread:commentCount'
    PLAYER_DECK: 'thread:playerDeck'
  TRADE:
    ITEMS: 'trade:items'
    USERS: 'trade:users'
  USER:
    DATA: 'user:data'
    IS_ONLINE: 'user:isOnline'
    FOLLOWER_COUNT: 'user:followerCount'
    GROUP_USER: 'user:groupUser'
    GROUP_USER_SETTINGS: 'user:groupUserSettings'
    GAME_DATA: 'user:gameData'
    IS_BANNED: 'user:isBanned'
    UPGRADES: 'user:upgrades'
  USER_ITEM:
    ITEM: 'userItem:item'
  USER_DATA:
    CONVERSATION_USERS: 'userData:conversationUsers'
    FOLLOWERS: 'userData:followers'
    FOLLOWING: 'userData:following'
    BLOCKED_USERS: 'userData:blockedUsers'

ONE_HOUR_SECONDS = 3600
ONE_DAY_SECONDS = 3600 * 24
FIVE_MINUTES_SECONDS = 60 * 5
LAST_ACTIVE_TIME_MS = 60 * 15
MAX_FRIENDS = 100 # FIXME add pagination
NEWBIE_CHEST_COUNT = 0
CHEST_COUNT = 300

profileDialogUserEmbed = [
  TYPES.USER.GAME_DATA, TYPES.USER.IS_BANNED, TYPES.USER.UPGRADES
]

getCachedChatUser = ({userId, username, groupId}) ->
  if userId
    key = "#{CacheService.PREFIXES.CHAT_USER}:#{userId}:#{groupId}"
    getFn = User.getById
  else
    key = "#{CacheService.PREFIXES.CHAT_USER_B_USERNAME}:#{username}:#{groupId}"
    getFn = User.getByUsername

  CacheService.preferCache key, ->
    getFn userId or username, {preferCache: true}
    .then embedFn {
      embed: profileDialogUserEmbed
      gameId: config.CLASH_ROYALE_ID
      groupId: groupId
    }
    .then User.sanitizeChat(null)
  , {expireSeconds: FIVE_MINUTES_SECONDS}

getCachedChatGroupUser = ({userId, groupId}) ->
  prefix = CacheService.PREFIXES.CHAT_GROUP_USER
  key = "#{prefix}:#{groupId}:#{userId}"
  CacheService.preferCache key, ->
    GroupUser.getByGroupIdAndUserId(
      groupId, userId, {preferCache: true}
    )
    .then embedFn {
      embed: [TYPES.GROUP_USER.XP, TYPES.GROUP_USER.ROLE_NAMES]
    }
  , {expireSeconds: FIVE_MINUTES_SECONDS}

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

      when TYPES.USER.GROUP_USER
        embedded.groupUser = GroupUser.getByGroupIdAndUserId(
          groupId, embedded.id
        )

      when TYPES.USER.GROUP_USER_SETTINGS
        embedded.groupUserSettings = GroupUser.getSettingsByGroupIdAndUserId(
          groupId, embedded.id
        )

      when TYPES.USER.GAME_DATA
        embedded.gameData = Player.getByUserIdAndGameId(
          embedded.id, gameId
        )

      when TYPES.USER.IS_ONLINE
        embedded.isOnline = moment(embedded.lastActiveTime)
                            .add(LAST_ACTIVE_TIME_MS)
                            .isAfter moment()

      when TYPES.USER.UPGRADES
        embedded.upgrades = UserUpgrade.getAllByUserId embedded.id

      when TYPES.USER.IS_BANNED
        embedded.isChatBanned = Ban.getByGroupIdAndUserId(
          groupId or config.EMPTY_UUID
          embedded.id
          {preferCache: true}
        )
        .then (ban) ->
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

      when TYPES.SPECIAL_OFFER.TRANSACTION
        embedded.transaction = SpecialOffer.getTransactionByUserIdAndOfferId(
          userId, embedded.id
        )

      when TYPES.SPECIAL_OFFER_TRANSACTION.SPECIAL_OFFER
        embedded.specialOffer = SpecialOffer.getById embedded.offerId

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

      when TYPES.CLASH_ROYALE_CARD.STATS
        embedded.stats = ClashRoyaleCard.getStatsByKey embedded.key

      when TYPES.CLASH_ROYALE_CARD.POPULAR_DECKS
        embedded.popularDecks = ClashRoyaleCard.getPopularDecksByKey(
          embedded.key, {preferCache: true}
        ).map (popularDeck) ->
          ClashRoyaleDeck.getById popularDeck.deckId
          .then embedFn {
            embed: [
              TYPES.CLASH_ROYALE_DECK.CARDS
              TYPES.CLASH_ROYALE_DECK.STATS
              TYPES.CLASH_ROYALE_DECK.COPY_URL
            ]
          }
          .then (deck) ->
            _.defaults {deck}, popularDeck

      # when TYPES.CLASH_ROYALE_CARD.BEST_DECKS
      #   # FIXME FIXME: cache
      #   embedded.popularDecks = ClashRoyaleCard.getPopularDecksByKey(
      #     embedded.key, {preferCache: true, limit: 200}
      #   ).map (popularDeck) ->
      #     ClashRoyaleDeck.getById popularDeck.deckId
      #     .then embedFn {
      #       embed: [
      #         TYPES.CLASH_ROYALE_DECK.CARDS
      #         TYPES.CLASH_ROYALE_DECK.STATS
      #       ]
      #     }
      #     .then (deck) ->
      #       _.defaults {deck}, popularDeck
      #   .then (decks) ->
      #     _.orderBy decks, (deck) ->
      #       console.log deck
      #       deck

      when TYPES.STAR.USER
        embedded.user = User.getById embedded.userId, {preferCache: true}
        .then embedFn {
          embed: profileDialogUserEmbed.concat [TYPES.USER.FOLLOWER_COUNT]
          gameId: config.CLASH_ROYALE_ID
        }
        .then User.sanitizePublic null

      when TYPES.USER_ITEM.ITEM
        embedded.item = Item.getByKey embedded.itemKey, {preferCache: true}

      when TYPES.STAR.GROUP
        embedded.group = Group.getById embedded.groupId
        .then Group.sanitizePublic null

      when TYPES.BAN.USER
        embedded.user = User.getById embedded.userId, {preferCache: true}
        .then embedFn {
          embed: profileDialogUserEmbed
          gameId: config.CLASH_ROYALE_ID
          groupId: groupId
        }
        .then User.sanitizePublic null

      when TYPES.CONVERSATION.USERS
        if embedded.userIds
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
        if embedded.type isnt 'public'
          embedded.userIds = GroupUser.getAllByGroupId embedded.id
                              .map ({userId}) -> userId

      when TYPES.GROUP.USER_COUNT
        if embedded.type isnt 'public' and embedded.userIds?.then
          embedded.userCount = embedded.userIds.then (userIds) ->
            userIds.length
        else if embedded.type isnt 'public' and embedded.userIds
          embedded.userCount = embedded.userIds.length
        else
          embedded.userCount = GroupUser.getCountByGroupId embedded.id, {
            preferCache: true
          }

      when TYPES.GROUP.USERS
        embedded.users = Promise.map embedded.userIds, (userId) ->
          User.getById userId, {preferCache: true}
        .map embedFn {embed: [TYPES.USER.IS_ONLINE]}
        .map User.sanitizePublic null

      when TYPES.GROUP.ME_GROUP_USER
        embedded.meGroupUser = GroupUser.getByGroupIdAndUserId(
          embedded.id, user.id
        )
        .then embedFn {embed: [TYPES.GROUP_USER.ROLES]}

      when TYPES.GROUP.CONVERSATIONS
        # # TODO: rm after 1/11/2017
        # embedded.meGroupUser ?= GroupUser.getByGroupIdAndUserId(
        #   embedded.id, user.id
        # )
        # .then embedFn {embed: [TYPES.GROUP_USER.ROLES]}

        embedded.conversations = embedded.meGroupUser.then (meGroupUser) ->
          Conversation.getAllByGroupId embedded.id
          .then (conversations) ->
            _.filter conversations, (conversation) ->
              GroupUser.hasPermission {
                meGroupUser
                permissions: [GroupUser.PERMISSIONS.READ_MESSAGE]
                channelId: conversation.id
              }

      when TYPES.GROUP.CLAN
        if not _.isEmpty embedded.clanIds
          embedded.clan = Clan.getByClanIdAndGameId(
            embedded.clanIds[0], config.CLASH_ROYALE_ID
          )

      when TYPES.GROUP_AUDIT_LOG.USER
        if embedded.userId
          embedded.user = User.getById embedded.userId, {preferCache: true}
          .then User.sanitizePublic(null)

      when TYPES.GROUP_AUDIT_LOG.TIME
        timeUuid = if typeof embedded.timeUuid is 'string' \
                   then cknex.getTimeUuidFromString embedded.timeUuid
                   else embedded.timeUuid
        embedded.time = timeUuid.getDate()

      when TYPES.GROUP_USER.ROLES
        embedded.roles = GroupRole.getAllByGroupId(
          embedded.groupId, {preferCache: true}
        ).then (roles) ->
          everyoneRole = _.find roles, {name: 'everyone'}
          groupUserRoles = _.filter _.map embedded.roleIds, (roleId) ->
            _.find roles, (role) ->
              "#{role.roleId}" is "#{roleId}"
          if everyoneRole
            groupUserRoles = groupUserRoles.concat everyoneRole

      when TYPES.GROUP_USER.ROLE_NAMES
        embedded.roleNames = GroupRole.getAllByGroupId(
          embedded.groupId, {preferCache: true}
        ).then (roles) ->
          groupUserRoleNames = _.filter _.map embedded.roleIds, (roleId) ->
            _.find(roles, (role) ->
              "#{role.roleId}" is "#{roleId}")?.name
          groupUserRoleNames = groupUserRoleNames.concat 'everyone'

      when TYPES.GROUP_USER.XP
        if embedded.userId
          embedded.xp = GroupUser.getXpByGroupIdAndUserId(
            embedded.groupId, embedded.userId
          )

      when TYPES.GROUP_USER.USER
        if embedded.userId
          embedded.user = User.getById embedded.userId
          .then User.sanitizePublic(null)

      when TYPES.CONVERSATION.LAST_MESSAGE
        embedded.lastMessage = \
          ChatMessage.getLastByConversationId embedded.id

      when TYPES.THREAD.COMMENTS
        key = CacheService.PREFIXES.THREAD_COMMENTS + ':' + embedded.id
        embedded.comments = CacheService.preferCache key, ->
          ThreadComment.getAllByThreadId embedded.id
          .map embedFn {embed: [TYPES.THREAD_COMMENT.USER]}
        , {expireSeconds: FIVE_MINUTES_SECONDS}

      when TYPES.THREAD.COMMENT_COUNT
        key = CacheService.PREFIXES.THREAD_COMMENT_COUNT + ':' + embedded.id
        embedded.commentCount = CacheService.preferCache key, ->
          ThreadComment.getCountByThreadId embedded.id
        , {expireSeconds: FIVE_MINUTES_SECONDS}

      when TYPES.THREAD.PLAYER_DECK
        key = CacheService.PREFIXES.THREAD_DECK + ':' + embedded.id
        if embedded.data.extras?.deckId
          embedded.playerDeck = CacheService.preferCache key, ->
            ClashRoyalePlayerDeck.getByDeckIdAndPlayerId(
              embedded.data.extras?.deckId
              embedded.data.extras?.playerId
            )
            .then embedFn {embed: [TYPES.CLASH_ROYALE_PLAYER_DECK.DECK]}
            .then (playerDeck) ->
              playerDeck = _.pick playerDeck, [
                'deck', 'wins', 'losses', 'draws'
                'gameType', 'playerId', 'deck'
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
          embedded.creator = getCachedChatUser {
            userId: embedded.creatorId
            groupId: groupId
          }
        else
          embedded.creator = null

      when TYPES.THREAD_COMMENT.CREATOR
        if groupId and embedded.creatorId
          embedded.creator = getCachedChatUser {
            userId: embedded.creatorId
            groupId: groupId
          }

      when TYPES.THREAD_COMMENT.GROUP_USER
        if groupId and embedded.creatorId
          embedded.groupUser = getCachedChatGroupUser {
            userId: embedded.creatorId, groupId: groupId
          }

      when TYPES.THREAD_COMMENT.TIME
        timeUuid = if typeof embedded.timeUuid is 'string' \
                   then cknex.getTimeUuidFromString embedded.timeUuid
                   else embedded.timeUuid
        embedded.time = timeUuid.getDate()

      when TYPES.CHAT_MESSAGE.TIME
        timeUuid = if typeof embedded.timeUuid is 'string' \
                   then cknex.getTimeUuidFromString embedded.timeUuid
                   else embedded.timeUuid
        embedded.time = timeUuid.getDate()

      when TYPES.CHAT_MESSAGE.USER
        if embedded.userId
          embedded.user = getCachedChatUser embedded
        else
          embedded.user = null

      when TYPES.CHAT_MESSAGE.GROUP_USER
        if embedded.groupId and embedded.userId
          embedded.groupUser = getCachedChatGroupUser {
            userId: embedded.userId, groupId: embedded.groupId
          }

      when TYPES.CHAT_MESSAGE.MENTIONED_USERS
        text = embedded.body
        mentions = _.map _.uniq(text?.match /\@[a-zA-Z0-9-]+/g), (find) ->
          find.replace '@', ''
        mentions = _.take mentions, 5 # so people don't abuse
        embedded.mentionedUsers = Promise.map mentions, (username) ->
          getCachedChatUser {username, groupId: embedded.groupId}

      when TYPES.TRADE.ITEMS
        # can't cache long since the items change frequently (circulation #)
        sendItemsKey = CacheService.PREFIXES.TRADE_SEND_ITEMS +
                       ':' + embedded.id
        receiveItemsKey = CacheService.PREFIXES.TRADE_RECEIVE_ITEMS +
                          ':' + embedded.id
        embedded.sendItems = CacheService.preferCache sendItemsKey, ->
          Promise.map embedded.sendItemKeys, (itemKey) ->
            if itemKey.itemKey
              Promise.props _.defaults {
                item: Item.getByKey(itemKey.itemKey)
              }, itemKey
          .filter (item) -> Boolean item?.item
        , {expireSeconds: ONE_HOUR_SECONDS}

        embedded.receiveItems = CacheService.preferCache receiveItemsKey, ->
          Promise.map embedded.receiveItemKeys, (itemKey) ->
            if itemKey.itemKey
              Promise.props _.defaults {
                item: Item.getByKey(itemKey.itemKey)
              }, itemKey
          .filter (item) -> Boolean item?.item
        , {expireSeconds: ONE_HOUR_SECONDS}
      when TYPES.TRADE.USERS
        fromId = embedded.fromId
        toId = embedded.toId
        embedded.from = if fromId \
                      then User.getById(fromId).then User.sanitizePublic(null)
                      else null
        embedded.to = if toId \
                      then User.getById(toId).then User.sanitizePublic(null)
                      else null

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

      when TYPES.CLASH_ROYALE_DECK.STATS
        embedded.stats = ClashRoyaleDeck.getStatsById embedded.deckId, {
          preferCache: true
        }

      when TYPES.CLASH_ROYALE_DECK.COPY_URL
        cardKeys = embedded.deckId.split '|'
        copyIds = _.map cardKeys, (key) ->
          cardIds[key]
        embedded.copyUrl = "clashroyale://copyDeck?deck=#{copyIds.join(';')}"

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
            .then ClashRoyaleCard.sanitizeLite(null)
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
          .then embedFn {
            embed: [
              TYPES.CLASH_ROYALE_DECK.CARDS
              TYPES.CLASH_ROYALE_DECK.COPY_URL
            ]
          }
          .then ClashRoyaleDeck.sanitize null
        , {expireSeconds: ONE_DAY_SECONDS}

      # else
      #   console.log 'no match found', key

  return Promise.props embedded

class EmbedService
  TYPES: TYPES
  embed: embedFn

module.exports = new EmbedService()
