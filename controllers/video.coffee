_ = require 'lodash'
router = require 'exoid-router'

Video = require '../models/video'
GroupUser = require '../models/group_user'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'

config = require '../config'

defaultEmbed = []

ONE_DAY_SECONDS = 3600 * 24

class VideoCtrl
  getAllByGroupId: ({groupId, sort}) ->
    Video.getAllByGroupId(groupId, {sort})
    .map EmbedService.embed {embed: defaultEmbed}
    .map Video.sanitize null

  getById: ({id}) ->
    Video.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then Video.sanitize null

  getByKey: ({key}) ->
    Video.getByKey key
    .then EmbedService.embed {embed: defaultEmbed}
    .then Video.sanitize null

  logViewById: ({id}, {user}) ->
    Video.getById id
    .then (video) ->
      prefix = CacheService.PREFIXES.VIDEO_DAILY_XP
      key = "#{prefix}:#{user.id}:#{video.groupId}"
      CacheService.runOnce key, ->
        GroupUser.incrementXpByGroupIdAndUserId(
          video.groupId
          user.id
          config.XP_AMOUNTS.DAILY_VIDEO_VIEW
        )
        .then ->
          config.XP_AMOUNTS.DAILY_VIDEO_VIEW
      , {expireSeconds: ONE_DAY_SECONDS}
    .then (xpGained) ->
      {xpGained}

module.exports = new VideoCtrl()
