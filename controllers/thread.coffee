_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Thread = require '../models/thread'
ThreadMessage = require '../models/thread_message'
EmbedService = require '../services/embed'
schemas = require '../schemas'

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

    Thread.create {title, userId}
    .then (thread) ->
      ThreadMessage.create {
        body
        userId
        threadId: thread.id
      }

  getAll: ->
    Thread.getAll()
    .map EmbedService.embed defaultEmbed
    .map Thread.sanitize null

  getById: ({id}, {user}) ->
    console.log 'gbid'
    Thread.getById id
    .then EmbedService.embed messagesEmbed
    .then Thread.sanitize null

module.exports = new ThreadCtrl()
