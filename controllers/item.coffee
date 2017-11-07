_ = require 'lodash'

Item = require '../models/item'

class ItemCtrl
  getAll: ({}, {user}) ->
    Item.getAll()

module.exports = new ItemCtrl()
