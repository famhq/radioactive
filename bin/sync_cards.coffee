_ = require 'lodash'
Promise = require 'bluebird'

cards = require '../resources/data/cards'
Card = require '../models/clash_royale_card'

# ruby ../clash-royale-data/parsers/clashroyaleguies.rb

snakeToCamel = (card) ->
  _.reduce card, (obj, value, property) ->
    if _.isInteger parseInt(value)
      value = parseInt value
    property = _.camelCase(property)
    property = property.replace /costs/, 'elixirCost'
    property = property.replace /cost/, 'elixirCost'
    obj[property] = value
    obj
  , {}

_.map cards, (card, name) ->
  data = snakeToCamel card
  data.levels = _.map data.levels, (level) -> snakeToCamel level
  console.log name
  key = _.snakeCase(name)
  key = key.replace 'p_e_k_k_a', 'pekka'
  key = key.replace 'spear_goblin', 'spear_goblins'
  key = key.replace 'archer', 'archers'
  key = key.replace '3395', 'mega_minion'
  key = key.replace 'clash_royale_skeleton_army', 'skeleton_army'
  Card.getByKey key
  .then (card) ->
    if card
      Card.updateByKey key, {data}
    else
      console.log 'create', key
      Card.create {
        key
        name: _.startCase key
        data
      }
