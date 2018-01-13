_ = require 'lodash'
router = require 'exoid-router'

Video = require '../models/video'
GroupUserXpTransaction = require '../models/group_user_xp_transaction'
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
      GroupUserXpTransaction.completeActionByGroupIdAndUserId(
        video.groupId
        user.id
        GroupUserXpTransaction.ACTIONS.dailyVideoView
      )
      .catch -> null
    .then (xpGained) ->
      {xpGained}

module.exports = new VideoCtrl()
