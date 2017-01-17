_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

GroupRecordType = require '../models/group_record_type'
Group = require '../models/group'
EmbedService = require '../services/embed'

allowedClientEmbeds = ['userValues']

class GroupRecordTypeCtrl
  create: ({name, timeScale, groupId}, {user}) ->
    router.assert {name, timeScale}, {
      name: Joi.string()
      timeScale: Joi.string()
    }

    Group.hasPermissionByIdAndUser groupId, user, {level: 'admin'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupRecordType.create {
        name
        timeScale
        groupId
        creatorId: user.id
      }

  # getById: ({id}, {user}) ->
  #   GroupRecordType.getById id
  #   .then EmbedService.embed {embed: defaultEmbed}

  getAllByGroupId: ({groupId, embed}, {user}) ->
    Group.hasPermissionByIdAndUser groupId, user, {level: 'admin'}
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      embed ?= []
      embed = _.filter embed, (item) ->
        allowedClientEmbeds.indexOf(item) isnt -1
      embed = _.map embed, (item) ->
        EmbedService.TYPES.GROUP_RECORD_TYPE[_.snakeCase(item).toUpperCase()]

      GroupRecordType.getAllByGroupId groupId
      .map EmbedService.embed {embed}

  deleteById: ({id}, {user}) ->
    GroupRecordType.getById id
    .then (groupRecordType) ->
      unless groupRecordType
        router.throw status: 404, info: 'record not found'
      Group.hasPermissionByIdAndUser groupRecordType.groupId, user, {
        level: 'admin'
      }
      .then (hasPermission) ->
        unless hasPermission
          router.throw status: 400, info: 'no permission'

        GroupRecordType.deleteById id

module.exports = new GroupRecordTypeCtrl()
