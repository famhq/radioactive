_ = require 'lodash'
Joi = require 'joi'
router = require 'exoid-router'

Lfg = require '../models/lfg'
User = require '../models/user'
Group = require '../models/group'
GroupUser = require '../models/group_user'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.LFG.USER]

class LfgCtrl
  getByGroupIdAndMe: ({groupId}, {user}) ->
    Group.getById groupId, {preferCache: true}
    .then (group) ->
      Lfg.getByGroupIdAndUserId groupId, user.id, {preferCache: true}
      .map EmbedService.embed {
        embed: defaultEmbed
        gameKeys: group?.gameKeys
      }

  getAllByGroupIdAndHashtag: ({groupId, hashtag}, {user}) ->
    if hashtag
      hashtag = "##{hashtag}"
    else
      hashtag = ''
    Group.getById groupId, {preferCache: true}
    .then (group) ->
      Lfg.getAllByGroupIdAndHashtag groupId, hashtag, {preferCache: true}
      .map EmbedService.embed {
        embed: defaultEmbed
        gameKeys: group?.gameKeys
      }

  upsert: ({groupId, text}, {user}) ->
    Lfg.getByGroupIdAndUserId groupId, user.id, {preferCache: true}
    .then (existingLfg) ->
      if existingLfg
        Lfg.deleteByLfg existingLfg
    .then ->
      Lfg.upsert {groupId, userId: user.id, text}

  deleteByGroupIdAndUserId: ({groupId, userId}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, [
      GroupUser.PERMISSIONS.DELETE_MESSAGE
    ]
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      Lfg.getByGroupIdAndUserId groupId, userId, {preferCache: true}
      .then Lfg.deleteByLfg

module.exports = new LfgCtrl()
