_ = require 'lodash'
Promise = require 'bluebird'
xRay = require 'x-ray'
tabletojson = require 'tabletojson'
request = require 'request-promise'

Card = require '../models/clash_royale_card'

getStats = (href) ->
  new Promise (resolve) ->
    x(href, ['#unit-attributes-table@html']) (err, table) ->
      if err
        console.log err
      table = tabletojson.convert "<table>#{table}</table"

      table = table[0][0]
      resolve _.reduce table, (obj, value, key) ->
        obj[_.camelCase(key)] = if isNaN(parseInt(value)) \
                                then value
                                else parseInt(value)
        obj
      , {}

getLevels = (href) ->
  new Promise (resolve) ->
    x(href, ['#unit-statistics-table@html']) (err, table) ->
      if err
        console.log err
      table = tabletojson.convert "<table>#{table}</table"

      table = table[0]
      resolve  _.map table, (level) ->
        _.reduce level, (obj, value, key) ->
          obj[_.camelCase(key)] = if isNaN(parseInt(value)) \
                                  then value
                                  else parseInt(value)
          obj
        , {}

getCards = ->
  new Promise (resolve) ->
    console.log 'try'
    url = 'http://clashroyale.wikia.com/wiki/Cards'
    x(url, ['.sortable a@href']) (err, links) ->
      x(url, ['.sortable a']) (err, names) ->
        resolve _.zip links, names

x = new xRay()
console.log 'try'
# request 'http://clashroyale.wikia.com/api/v1/Navigation/Data', {json: true}
# .then ({navigation}) ->
#   console.log 'get', navigation.wiki
#   items = _.find navigation.wiki, {text: 'Cards'}
#   items = _.filter items.children, ({text}) ->
#     console.log text
#     text.indexOf('Cards') isnt -1
getCards()
.then (cards) ->
  _.map cards, ([href, text]) ->
    # href = "http://clashroyale.wikia.com#{href}"
    console.log 'req', "http://clashroyale.wikia.com#{href}"
    Promise.all [
      getStats href
      getLevels href
    ]
    .then ([stats, levels]) ->
      console.log 'got', "http://clashroyale.wikia.com#{href}"
      cardData = _.defaults stats, {levels}

      cardKey = _.snakeCase text
      cardKey = cardKey.replace 'p_e_k_k_a', 'pekka'
      # console.log cardKey, cardData

      Card.getByKey cardKey
      .then (card) ->
        if card
          console.log 'update', cardKey
          Card.updateByKey cardKey, {data: cardData}
        else
          console.log 'create', cardKey
          Card.create {
            key: cardKey
            name: _.startCase cardKey
            data: cardData
          }





# x = new xRay()
# find = {
#   cardNames: ['.su-column-inner li a']
#   hrefs: ['.su-column-inner li a@href']
# }
# i = 0
# x('http://clashroyalearena.com/cards', find) (err, {cardNames, hrefs}) ->
#   cards = _.zip cardNames, hrefs
#   # return console.log cards.length
#   cards = _.map cards, ([cardName, href]) ->
#     cardKey = _.snakeCase cardName.toLowerCase().replace /\./g, ''
#     cardKey = cardKey.replace 'the_log', 'log'
#     cardKey = cardKey.replace '_spell', ''
#     cardKey = cardKey.replace /spear_goblin$/, 'spear_goblins'
#     cardKey = cardKey.replace 'bomber_tower', 'bomb_tower'
#     x(href, ['.su-table@html']) (err, tables) ->
#       if err
#         console.log err
#       unless tables
#         return
#       i += 1
#       statsTable =  tabletojson.convert tables[0]
#       levelsTable = tabletojson.convert tables[1]
#
#       statsHeaders = _.values statsTable[0][0]
#       statsValues = statsTable[0][1]
#       stats = _.reduce statsHeaders, (obj, statName, i) ->
#         obj[_.camelCase(statName)] = statsValues[i]
#         obj
#       , {}
#
#       levelsHeaders = _.values levelsTable[0][0]
#       levelsHeaders = _.map levelsHeaders, _.camelCase
#       levels = _.takeRight levelsTable[0], levelsTable[0].length - 1
#       levels = _.map levels, (levelValues) ->
#         levelValues = _.values levelValues
#         levelValues = _.map levelValues, (value) ->
#           if _.isInteger parseInt(value)
#             value = parseInt value
#           value
#         _.zipObject levelsHeaders, levelValues
#
#       cardData = _.defaults stats, {levels}
#
#       Card.getByKey cardKey
#       .then (card) ->
#         if card
#           console.log 'update', cardKey
#           Card.updateByKey cardKey, {data: cardData}
#         else
#           console.log 'create', cardKey
#           Card.create {
#             key: cardKey
#             name: _.startCase cardKey
#             data: cardData
#           }















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
