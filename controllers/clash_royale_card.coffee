_ = require 'lodash'
router = require 'exoid-router'

ClashRoyaleCard = require '../models/clash_royale_card'
EmbedService = require '../services/embed'

schemas = require '../schemas'

defaultEmbed = []

class ClashRoyaleCardCtrl
  getAll: ({sort}) ->
    ClashRoyaleCard.getAll({sort})
    .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleCard.sanitize null

  getById: ({id}) ->
    ClashRoyaleCard.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleCard.sanitize null

module.exports = new ClashRoyaleCardCtrl()
