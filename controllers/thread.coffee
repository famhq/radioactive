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
    Thread.getById id
    .then EmbedService.embed defaultEmbed
    .then Thread.sanitize

module.exports = new ThreadCtrl()
