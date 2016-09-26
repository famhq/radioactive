_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Conversation = require '../models/conversation'
EmbedService = require '../services/embed'
schemas = require '../schemas'

defaultEmbed = [EmbedService.TYPES.CONVERSATION.MESSAGES]

class ConversationCtrl
  getAll: ({}, {user}) ->
    Conversation.getAllByUserId user.id
    .map Conversation.sanitize null

  getById: ({id}, {user}) ->
    Conversation.getById id
    .then EmbedService.embed defaultEmbed
    .then (conversation) ->
      {messages, userId1, userId2} = conversation
      unless userId1 is user.id or userId2 is user.id
        router.throw status: 400, detail: 'no permission'

        Conversation.sanitize conversation

module.exports = new ConversationCtrl()
