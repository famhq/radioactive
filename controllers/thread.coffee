_ = require 'lodash'

User = require '../models/user'
UserData = require '../models/user_data'
Thread = require '../models/thread'
ThreadComment = require '../models/thread_comment'
EmbedService = require '../services/embed'

defaultEmbed = [
  EmbedService.TYPES.THREAD.FIRST_MESSAGE
  EmbedService.TYPES.THREAD.MESSAGE_COUNT
]
messagesEmbed = [
  EmbedService.TYPES.THREAD.MESSAGES
]

class ThreadCtrl
  create: ({title, body}, {user}) ->
    userId = user.id

    Thread.create {title, userId, body}

  getAll: ({}, {user}) ->
    Thread.getAll()
    .map EmbedService.embed {embed: defaultEmbed}
    .map Thread.sanitize null

  getById: ({id}, {user}) ->
    UserData.getByUserId user.id
    .then (userData) ->
      Thread.getById id
      .then EmbedService.embed {embed: messagesEmbed}
      .then (thread) ->
        thread?.messages = _.filter thread.messages, (message) ->
          userId = message.user?.id or 0
          (
            not message.user?.flags?.isChatBanned or user.flags.isModerator
          ) and userData.blockedUserIds?.indexOf(userId) is -1
        thread
      .then Thread.sanitize null

module.exports = new ThreadCtrl()
