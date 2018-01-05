_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserData = require '../models/user_data'
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

  updateMe: (diff, {user}) ->
    keys = ['presetAvatarId', 'unreadGroupInvites']
    UserData.upsertByUserId user.id, _.pick diff, keys

  blockByUserId: ({userId}, {user}) ->
    otherUserId = userId
    valid = Joi.validate {otherUserId}, {
      otherUserId: schemas.user.id
    }, {presence: 'required'}

    if valid.error
      router.throw status: 400, info: valid.error.message

    User.getById userId
    .then (otherUser) ->
      if otherUser.flags.isModerator
        return
      UserData.getByUserId otherUser.id
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
