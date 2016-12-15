_ = require 'lodash'
router = require 'exoid-router'

User = require '../models/user'
Conversation = require '../models/conversation'
Group = require '../models/group'
EmbedService = require '../services/embed'

defaultEmbed = [EmbedService.TYPES.CONVERSATION.USERS]
lastMessageEmbed = [
  EmbedService.TYPES.CONVERSATION.LAST_MESSAGE
  EmbedService.TYPES.CONVERSATION.USERS
]

class ConversationCtrl
  create: ({userIds, groupId}, {user}) ->
    userIds ?= []
    userIds = _.uniq userIds.concat [user.id]

    (if groupId
    then Conversation.getByGroupId groupId
    else Conversation.getByUserIds userIds)
    .then (conversation) ->
      return conversation or Conversation.create {
        userIds
        userData: _.zipObject userIds, _.map (userId) ->
          {
            isRead: userId is user.id
          }
      }

  getAll: ({}, {user}) ->
    Conversation.getAllByUserId user.id
    .map EmbedService.embed lastMessageEmbed
    .map Conversation.sanitize null

  getById: ({id}, {user}) ->
    Conversation.getById id
    .then EmbedService.embed defaultEmbed
    .tap (conversation) ->
      if conversation.userIds.indexOf(user.id) is -1
        router.throw status: 400, info: 'no permission'

      Conversation.markRead conversation, user.id
    .then Conversation.sanitize null

  getByGroupId: ({groupId}, {user}) ->
    Group.hasPermissionById groupId, user.id
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      Conversation.getByGroupId groupId
      .then (conversation) ->
        if conversation
          conversation
        else
          Conversation.create {
            groupId: groupId
          }
      .then  Conversation.sanitize null

module.exports = new ConversationCtrl()
