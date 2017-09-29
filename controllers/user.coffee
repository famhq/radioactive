_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'
geoip = require 'geoip-lite'

User = require '../models/user'
UserData = require '../models/user_data'
UserPlayer = require '../models/user_player'
EmbedService = require '../services/embed'
ImageService = require '../services/image'
CacheService = require '../services/cache'
schemas = require '../schemas'
config = require '../config'

TWELVE_HOURS_SECONDS = 3600 * 12
GET_ALL_LIMIT = 20
AVATAR_SMALL_IMAGE_WIDTH = 96
AVATAR_SMALL_IMAGE_HEIGHT = 96
AVATAR_LARGE_IMAGE_WIDTH = 512
AVATAR_LARGE_IMAGE_HEIGHT = 512
LAST_ACTIVE_UPDATE_FREQ_MS = 60 * 10 * 1000 # 10 min

defaultEmbed = [EmbedService.TYPES.USER.DATA]

class UserCtrl
  getMe: ({}, {user, headers, connection}) ->
    start = Date.now()
    EmbedService.embed {embed: defaultEmbed}, user
    .tap ->
      ip = headers['x-forwarded-for'] or
            connection.remoteAddress
      isRecent =
        user.lastActiveTime.getTime() < Date.now() - LAST_ACTIVE_UPDATE_FREQ_MS
      # rendered via starfire server (wrong ip)
      isServerSide = ip?.indexOf('::ffff:10.') isnt -1
      if (isRecent or not user.ip) and not isServerSide
        diff = {
          lastActiveIp: ip
          lastActiveTime: new Date()
        }
        unless user.ip
          diff.ip = ip
        User.updateById user.id, diff
      null # don't block
    .then User.sanitize null


  getById: ({id}) ->
    User.getById id
    .then User.sanitize(null)

  getByUsername: ({username}) ->
    User.getByUsername username
    .then User.sanitize(null)

  setFlags: (flags, {user}) ->
    flagsSchema =
      isAddressSkipped: Joi.boolean().optional()

    updateValid = Joi.validate flags, flagsSchema

    if updateValid.error
      router.throw status: 400, info: updateValid.error.message

    User.updateById user.id, {flags}

  setFlagsById: ({flags, id}, {user}) ->
    unless user.flags.isModerator
      router.throw status: 400, info: 'no permission'

    flagsSchema =
      isChatBanned: Joi.boolean().optional()

    updateValid = Joi.validate flags, flagsSchema

    if updateValid.error
      router.throw status: 400, info: updateValid.error.message

    User.updateById id, {flags}
    .then ->
      key = "#{CacheService.PREFIXES.CHAT_USER}:#{id}"
      CacheService.deleteByKey key

  updateById: ({id, diff}, {user}) ->
    flagsSchema =
      lastPlatform: Joi.string().optional()
      isChatBanned: Joi.boolean().optional()

    userUpdateSchema =
      flags: Joi.object().keys flagsSchema

    diff = _.pick diff, _.keys(userUpdateSchema)
    diff.flags = _.pick diff.flags, _.keys(flagsSchema)
    updateValid = Joi.validate diff, userUpdateSchema

    if updateValid.error
      router.throw status: 400, info: updateValid.error.message

    if diff.flags?.isChatBanned and not user.flags.isModerator
      router.throw
        status: 400
        info: 'You don\'t have permission to do that'

    if id and not _.isEmpty diff
      User.updateById id, diff
      .tap ->
        if diff.flags?.isChatBanned
          key = "#{CacheService.PREFIXES.CHAT_USER}:#{id}"
          CacheService.deleteByKey key
      .then ->
        null

  getAllByPlayerIdAndGameId: ({playerId, gameId}) ->
    UserPlayer.getAllByPlayerIdAndGameId playerId, gameId
    .then (userPlayers) ->
      userIds = _.map userPlayers, 'userId'
      verifiedUserPlayer = _.find userPlayers, {isVerified: true}
      verifiedUser = if verifiedUserPlayer \
                      then User.getById verifiedUserPlayer.userId
                      else Promise.resolve null

      Promise.all [
        verifiedUser
        .then User.sanitizePublic null

        User.getLastActiveByIds userIds
        .then User.sanitizePublic null
      ]
      .then ([verifiedUser, lastActiveUser]) ->
        {
          verifiedUser
          lastActiveUser
        }

  searchByUsername: ({username}) ->
    unless username
      router.throw status: 400, info: 'must enter a username'

    username = username.toLowerCase()

    key = "#{CacheService.PREFIXES.USERNAME_SEARCH}:#{username}"
    CacheService.preferCache key, ->
      User.getAllByUsername username, {limit: GET_ALL_LIMIT}
      .map EmbedService.embed {
        embed: [EmbedService.TYPES.USER.IS_BANNED]
      }
      .map User.sanitizePublic null
    , {expireSeconds: TWELVE_HOURS_SECONDS}

  setUsername: ({username}, {user}) ->
    username = username?.toLowerCase()
    router.assert {username}, {
      username: schemas.user.username
    }

    User.getByUsername username
    .then (existingUser) ->
      if existingUser?
        router.throw status: 400, info: "username taken: #{username}"
      User.updateById user.id, {username}
    .tap ->
      key = "#{CacheService.PREFIXES.CHAT_USER}:#{user.id}"
      CacheService.deleteByKey key
      null
    .then ->
      User.getById user.id
    .then User.sanitize(user.id)

  setAvatarImage: ({}, {user, file}) ->
    router.assert {file}, {
      file: Joi.object().unknown().keys schemas.imageFile
    }

    # bust cache
    keyPrefix = "images/starfire/u/#{user.id}/avatar_#{Date.now()}"

    Promise.all [
      ImageService.uploadImage
        key: "#{keyPrefix}.original.png"
        stream: ImageService.toStream
          buffer: file.buffer
          quality: 100

      ImageService.uploadImage
        key: "#{keyPrefix}.small.png"
        stream: ImageService.toStream
          buffer: file.buffer
          width: AVATAR_SMALL_IMAGE_WIDTH
          height: AVATAR_SMALL_IMAGE_HEIGHT

      ImageService.uploadImage
        key: "#{keyPrefix}.large.png"
        stream: ImageService.toStream
          buffer: file.buffer
          width: AVATAR_LARGE_IMAGE_WIDTH
          height: AVATAR_LARGE_IMAGE_HEIGHT
    ]
    .then (imageKeys) ->
      _.map imageKeys, (imageKey) ->
        "https://#{config.CDN_HOST}/#{imageKey}"
    .then ([originalUrl, smallUrl, largeUrl]) ->
      avatarImage =
        originalUrl: originalUrl
        versions: [
          {
            width: AVATAR_SMALL_IMAGE_WIDTH
            height: AVATAR_SMALL_IMAGE_HEIGHT
            url: smallUrl
          }
          {
            width: AVATAR_LARGE_IMAGE_WIDTH
            height: AVATAR_LARGE_IMAGE_HEIGHT
            url: largeUrl
          }
        ]
      Promise.all [
        User.updateById user.id, {avatarImage: avatarImage}
        UserData.upsertByUserId user.id, {presetAvatarId: null}
      ]
    .then (response) ->
      key = "#{CacheService.PREFIXES.CHAT_USER}:#{user.id}"
      CacheService.deleteByKey key
      response
    .then ->
      User.getById user.id
    .then User.sanitize(user.id)

module.exports = new UserCtrl()
