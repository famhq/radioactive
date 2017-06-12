_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
ClashRoyaleMatch = require '../models/clash_royale_match'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [
  EmbedService.TYPES.CLASH_ROYALE_MATCH.DECK
]

class ClashRoyaleMatchCtrl
  getAllByUserId: ({userId, sort, filter}, {user}) ->
    ClashRoyaleMatch.getAllByUserId userId, {sort}
    .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleMatch.sanitize null

module.exports = new ClashRoyaleMatchCtrl()
