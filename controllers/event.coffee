_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'
Promise = require 'bluebird'
uuid = require 'uuid'

Event = require '../models/event'
Group = require '../models/group'
Conversation = require '../models/conversation'
EmbedService = require '../services/embed'
r = require '../services/rethinkdb'
schemas = require '../schemas'

allowedClientEmbeds = ['userValues']

usersEmbed = [EmbedService.TYPES.EVENT.USERS]
defaultEmbed = [EmbedService.TYPES.EVENT.CREATOR]

class EventCtrl
  create: (diff, {user}) =>
    @validateAndCheckPermissions diff, {user}
    .then (diff) ->
      conversationId = uuid.v4()
      Event.create _.defaults diff, {
        creatorId: user.id
        userIds: [user.id]
        conversationId: conversationId
      }
      .tap ({id}) ->
        Conversation.create {
          id: conversationId
          userIds: [user.id]
          eventId: id
        }

  validateAndCheckPermissions: (diff, {user}) ->
    diff = _.pick diff, _.keys schemas.event
    diff.startTime = new Date diff.startTime
    diff.endTime = new Date diff.endTime
    diff.maxUserCount = parseInt diff.maxUserCount
    router.assert diff, schemas.event

    if diff.groupId
      hasPermission = Group.hasPermissionByIdAndUser diff.groupId, user, {
        level: 'admin'
      }
    else
      hasPermission = Promise.resolve true

    hasPermission
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'
      diff

  updateById: (diff, {user}) =>
    id = diff.id
    Promise.all [
      Event.getById id
      @validateAndCheckPermissions diff, {user}
    ]
    .then ([event, diff]) ->
      hasPermission = Event.hasPermission event, user, {
        level: 'admin'
      }
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      Event.updateById id, diff

  joinById: ({id}, {user}) ->
    Event.getById id
    .then (event) ->
      isInEvent = event.userIds.indexOf(user.id) isnt -1
      isGroupOnly = event.visibility is 'group'

      if event.userIds.length > event.maxUserCount
        router.throw status: 400, info: 'event is full'

      if not isInEvent and not isGroupOnly
        Event.updateById event.id, {
          userIds: r.row('userIds').append user.id
        }
      else if not isInEvent and isGroupOnly
        null # TODO

  leaveById: ({id}, {user}) ->
    hasPermission = Event.hasPermissionByIdAndUser id, user, {
      level: 'member'
    }
    unless hasPermission
      router.throw status: 400, info: 'no permission'

    Event.updateById id, {
      userIds: r.row('userIds').difference [user.id]
    }

  deleteById: ({id}, {user}) ->
    hasPermission = Event.hasPermissionByIdAndUser id, user, {
      level: 'admin'
    }
    unless hasPermission
      router.throw status: 400, info: 'no permission'

    Event.deleteById id

  getById: ({id}, {user}) ->
    Event.getById id
    .then EmbedService.embed {embed: usersEmbed}
    .then Event.sanitizePublic null

  getAll: ({filter}, {user}) ->
    Event.getAll {filter, user}
    .map EmbedService.embed {embed: defaultEmbed}
    .map Event.sanitizePublic null

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

      Event.getAllByGroupId groupId
      .map EmbedService.embed {embed}

module.exports = new EventCtrl()
