_ = require 'lodash'
router = require 'exoid-router'

weapons = require '../resources/data/fortnite_weapons.json'

class FortniteWeaponCtrl
  getAll: ({}, {user}) ->
    Promise.resolve weapons

module.exports = new FortniteWeaponCtrl()
