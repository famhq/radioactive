_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

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
    # .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleMatch.sanitize null

  getAllByPlayerId: ({playerId, sort, limit, filter, cursor}, {user}) ->
    ClashRoyaleMatch.getAllByPlayerId playerId, {sort, limit, cursor}
    .then ({rows, cursor}) ->
      Promise.props {
        results: _.filter _.map rows, ClashRoyaleMatch.sanitize null
        cursor
      }

module.exports = new ClashRoyaleMatchCtrl()
