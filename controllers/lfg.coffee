_ = require 'lodash'
Joi = require 'joi'
router = require 'exoid-router'

Lfg = require '../models/lfg'
User = require '../models/user'
Ban = require '../models/ban'
Group = require '../models/group'
GroupUser = require '../models/group_user'
EmbedService = require '../services/embed'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.LFG.USER]

class LfgCtrl
  _checkIfBanned: (groupId, ipAddr, userId, router) ->
    ipAddr ?= 'n/a'
    Promise.all [
      Ban.getByGroupIdAndIp groupId, ipAddr, {preferCache: true}
      Ban.getByGroupIdAndUserId groupId, userId, {preferCache: true}
      Ban.isHoneypotBanned ipAddr, {preferCache: true}
    ]
    .then ([bannedIp, bannedUserId, isHoneypotBanned]) ->
      if bannedIp?.ip or bannedUserId?.userId or isHoneypotBanned
        router.throw
          status: 403
          info: "unable to post, banned #{userId}, #{ipAddr}"

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

  upsert: ({groupId, text}, {user, headers, connection}) =>
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    @_checkIfBanned groupId, ip, user.id, router
    .then ->
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
