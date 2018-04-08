_ = require 'lodash'
router = require 'exoid-router'

Video = require '../models/video'
EarnAction = require '../models/earn_action'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'

config = require '../config'

defaultEmbed = []

ONE_DAY_SECONDS = 3600 * 24

class VideoCtrl
  getAllByGroupId: ({groupId, sort, limit}) ->
    Video.getAllByGroupId(groupId, {sort, limit, preferCache: true})
    .map EmbedService.embed {embed: defaultEmbed}
    .map Video.sanitize null

  getById: ({id}) ->
    Video.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then Video.sanitize null

  logViewById: ({id}, {user}) ->
    Video.getById id
    .then (video) ->
      EarnAction.completeActionByGroupIdAndUserId(
        video.groupId
        user.id
        'videoView'
      )
      .catch -> null
    .then (rewards) ->
      {rewards}

module.exports = new VideoCtrl()
