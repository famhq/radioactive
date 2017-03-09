_ = require 'lodash'
Promise = require 'bluebird'
xRay = require 'x-ray'
tabletojson = require 'tabletojson'

Card = require '../models/clash_royale_card'

x = new xRay()
find = {
  cardNames: ['.su-column-inner li a']
  hrefs: ['.su-column-inner li a@href']
}
x('http://clashroyalearena.com/cards', find) (err, {cardNames, hrefs}) ->
  cards = _.zip cardNames, hrefs
  # return console.log cards.length
  cards = _.map cards, ([cardName, href]) ->
    cardKey = _.snakeCase cardName.toLowerCase().replace /\./g, ''
    x(hrefs[0], ['.su-table@html']) (err, tables) ->
      statsTable =  tabletojson.convert tables[0]
      levelsTable = tabletojson.convert tables[1]

      statsHeaders = _.values statsTable[0][0]
      statsValues = statsTable[0][1]
      stats = _.reduce statsHeaders, (obj, statName, i) ->
        obj[_.camelCase(statName)] = statsValues[i]
        obj
      , {}

      levelsHeaders = _.values levelsTable[0][0]
      levelsHeaders = _.map levelsHeaders, _.camelCase
      levels = _.takeRight levelsTable[0], levelsTable[0].length - 1
      levels = _.map levels, (levelValues) ->
        levelValues = _.values levelValues
        levelValues = _.map levelValues, (value) ->
          if _.isInteger parseInt(value)
            value = parseInt value
          value
        _.zipObject levelsHeaders, levelValues

      cardData = _.defaults stats, {levels}

      Card.getByKey cardKey
      .then (card) ->
        if card
          Card.updateByKey cardKey, {data: cardData}
        else
          console.log 'create', cardKey
          Card.create {
            key: cardKey
            name: _.startCase cardKey
            data: cardData
          }
# return
#
# snakeToCamel = (card) ->
#   _.reduce card, (obj, value, property) ->
#     if _.isInteger parseInt(value)
#       value = parseInt value
#     property = _.camelCase(property)
#     property = property.replace /costs/, 'elixirCost'
#     property = property.replace /cost/, 'elixirCost'
#     obj[property] = value
#     obj
#   , {}
#
# _.map cards, (card, name) ->
#   data = snakeToCamel card
#   data.levels = _.map data.levels, (level) -> snakeToCamel level
#   console.log name
#   key = _.snakeCase(name)
#   key = key.replace 'p_e_k_k_a', 'pekka'
#   key = key.replace 'spear_goblin', 'spear_goblins'
#   key = key.replace 'archer', 'archers'
#   key = key.replace '3395', 'mega_minion'
#   key = key.replace 'clash_royale_skeleton_army', 'skeleton_army'
#   Card.getByKey key
#   .then (card) ->
#     if card
#       Card.updateByKey key, {data}
#     else
#       console.log 'create', key
#       Card.create {
#         key
#         name: _.startCase key
#         data
#       }
