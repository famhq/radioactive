_ = require 'lodash'
router = require 'exoid-router'

Video = require '../models/video'
EmbedService = require '../services/embed'

schemas = require '../schemas'

defaultEmbed = []

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

module.exports = new VideoCtrl()
