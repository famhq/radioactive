_ = require 'lodash'

Item = require '../models/item'

class ItemCtrl
  getAllByGroupId: ({groupId}, {user}) ->
    Item.getAllByGroupId groupId

module.exports = new ItemCtrl()
