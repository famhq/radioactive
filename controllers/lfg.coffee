_ = require 'lodash'
Joi = require 'joi'
router = require 'exoid-router'

UserBlock = require '../models/user_block'
User = require '../models/user'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.USER_BLOCK.USER]

class LfgCtrl
  getAll: ({userId}, {user}) ->
    userId ?= user.id
    UserBlock.getAllByUserId userId, {preferCache: true}
    .map EmbedService.embed {embed: defaultEmbed}

  getAllIds: ({userId}, {user}) ->
    userId ?= user.id
    UserBlock.getAllByUserId userId, {preferCache: true}
    .map (userBlock) ->
      userBlock.blockedId

  upsert: ({groupId, userId, text}, {user}) ->
    # TODO: check for existing
    UserBlock.upsert {groupId, userId, text}


module.exports = new LfgCtrl()
