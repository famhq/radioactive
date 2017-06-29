_ = require 'lodash'

Star = require '../models/star'
EmbedService = require '../services/embed'

defaultEmbed = [
  EmbedService.TYPES.STAR.USER
  EmbedService.TYPES.STAR.GROUP
]

class StarCtrl
  getByUsername: ({username}, {user}) ->
    Star.getByUsername username
    .then EmbedService.embed {embed: defaultEmbed}

  getAll: ({}, {user}) ->
    Star.getAll()
    .map EmbedService.embed {embed: defaultEmbed}

module.exports = new StarCtrl()
