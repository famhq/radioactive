_ = require 'lodash'

UserItem = require '../models/user_item'
EmbedService = require '../services/embed'

defaultEmbed = [
  EmbedService.TYPES.USER_ITEM.ITEM
]

class UserItemCtrl
  getAll: ({}, {user}) ->
    UserItem.getAllByUserId user.id
    .map EmbedService.embed {embed: defaultEmbed}

module.exports = new UserItemCtrl()
