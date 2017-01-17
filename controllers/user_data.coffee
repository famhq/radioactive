_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserData = require '../models/user_data'
ClashRoyaleUserDeck = require '../models/clash_royale_user_deck'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
PushNotificationService = require '../services/push_notification'
config = require '../config'
schemas = require '../schemas'

defaultEmbed = []
allowedClientEmbeds = ['following', 'followers', 'blockedUsers']

class UserDataCtrl
  getMe: ({embed} = {}, {user}) ->
    embed ?= defaultEmbed
    embed = _.filter embed, (item) -> allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.USER_DATA[_.snakeCase(item).toUpperCase()]
    UserData.getByUserId user.id
    .then EmbedService.embed {embed}

  getByUserId: ({userId, embed} = {}) ->
    embed ?= defaultEmbed
    embed = _.filter embed, (item) -> allowedClientEmbeds.indexOf(item) isnt -1
    embed = _.map embed, (item) ->
      EmbedService.TYPES.USER_DATA[_.snakeCase(item).toUpperCase()]
    UserData.getByUserId userId
    .then EmbedService.embed {embed}

  setAddress: ({country, address, city, zip}, {user}) ->
    UserData.upsertByUserId user.id, {address: {country, address, city, zip}}

  setClashRoyaleDeckId: ({clashRoyaleDeckId}, {user}) ->
    Promise.all [
      ClashRoyaleUserDeck.upsertByDeckIdAndUserId(
        clashRoyaleDeckId, user.id, {isFavorited: true}
      )
      UserData.upsertByUserId user.id, {clashRoyaleDeckId}
    ]

  updateMe: (diff, {user}) ->
    keys = ['presetAvatarId', 'unreadGroupInvites']
    UserData.upsertByUserId user.id, _.pick diff, keys

  followByUserId: ({userId}, {user}) ->
    otherUserId = userId
    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    Promise.all [
      UserData.getByUserId user.id
      UserData.getByUserId otherUserId
      User.getById otherUserId
    ]
    .then ([userData, otherUserData, otherUser]) ->
      if userData.followingIds.indexOf(otherUserId) isnt -1
        router.throw status: 400, info: 'already following'
      unless otherUserData
        router.throw status: 404, info: 'user not found'
      if otherUserData.followerIds.indexOf(user.id) isnt -1
        router.throw status: 400, info: 'already following'

      Promise.all [
        UserData.upsertByUserId user.id, {
          followingIds: userData.followingIds.concat [otherUserId]
        }
        UserData.upsertByUserId otherUserData.userId, {
          followerIds: otherUserData.followerIds.concat [user.id]
      }
      ]
      .then ->
        PushNotificationService.send otherUser, {
          title: 'New friend'
          type: PushNotificationService.TYPES.NEW_FRIEND
          url: "https://#{config.SUPERNOVA_HOST}"
          text: "#{User.getDisplayName(user)} added you as a friend"
          data: {path: '/friends'}
        }
        .catch -> null
        key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWERS}:#{otherUserId}"
        CacheService.deleteByKey key
        key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING}:#{user.id}"
        CacheService.deleteByKey key
        null

  unfollowByUserId: ({userId}, {user}) ->
    otherUserId = userId
    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    Promise.all [
      UserData.getByUserId user.id
      UserData.getByUserId otherUserId
    ]
    .then ([userData, otherUserData]) ->
      if userData.followingIds.indexOf(otherUserId) is -1
        router.throw status: 400, info: 'not following'

      if otherUserData and otherUserData.followerIds.indexOf(user.id) isnt -1
        UserData.upsertByUserId otherUserId, {
          followerIds:
            _.filter otherUserData.followerIds, (userId) ->
              userId isnt user.id
        }
      UserData.upsertByUserId user.id, {
        followingIds:
          _.filter userData.followingIds, (followingId) ->
            followingId isnt otherUserId
      }
    .then ->
      key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWERS}:#{otherUserId}"
      CacheService.deleteByKey key
      key = "#{CacheService.PREFIXES.USER_DATA_FOLLOWING}:#{user.id}"
      CacheService.deleteByKey key
      null


  blockByUserId: ({userId}, {user}) ->
    otherUserId = userId
    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    UserData.getByUserId user.id
    .then (userData) ->
      UserData.upsertByUserId user.id, {
        blockedUserIds: _.uniq userData.blockedUserIds.concat([otherUserId])
      }
    .then ->
      key = CacheService.PREFIXES.USER_DATA_BLOCKED_USERS + ':' + user.id
      CacheService.deleteByKey key
      null # don't block load

  unblockByUserId: ({userId}, {user}) ->
    otherUserId = userId

    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    UserData.getByUserId user.id
    .then (userData) ->
      if userData.blockedUserIds.indexOf(otherUserId) is -1
        router.throw status: 400, info: 'not blocked'

      UserData.upsertByUserId user.id, {
        blockedUserIds: _.filter userData.blockedUserIds, (blockedUserId) ->
          blockedUserId isnt otherUserId
      }
      .then ->
        key = CacheService.PREFIXES.USER_DATA_BLOCKED_USERS + ':' + user.id
        CacheService.deleteByKey key
        null # don't block

  deleteConversationByUserId: ({userId}) ->
    otherUserId = userId

    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    UserData.getByUserId user.id
    .then (userData) ->
      newConversationUserIds = _.filter userData.conversationUserIds, (id) ->
        id isnt otherUserId

      newConversationUserIds = _.take(
        newConversationUserIds, MAX_CONVERSATION_USER_IDS
      )

      UserData.upsertByUserId user.id, {
        conversationUserIds: newConversationUserIds
      }
    .then ->
      key = "#{CacheService.PREFIXES.USER_DATA_CONVERSATION_USERS}:#{user.id}"
      CacheService.deleteByKey key
      null


module.exports = new UserDataCtrl()
