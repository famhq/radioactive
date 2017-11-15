_ = require 'lodash'

Item = require '../models/item'

class ItemCtrl
  getAll: ({}, {user}) ->
    Item.getAll()

  getAllByGroupId: ({groupId}, {user}) ->
    Item.getAllByGroupId groupId

module.exports = new ItemCtrl()
