_ = require 'lodash'
router = require 'exoid-router'

ClashRoyaleCard = require '../models/clash_royale_card'
EmbedService = require '../services/embed'

schemas = require '../schemas'

defaultEmbed = []

# https://docs.google.com/spreadsheets/d/1TWLbxIwCjLL-kRMpzg56raAUsTQJr906fFKEEG1cpN0/edit#gid=0
# http://clashroyale.wikia.com/wiki/Card_Chance_Calculator
# http://clashroyale.wikia.com/wiki/Chests
chests =
  arena11:
    giant:
      cards: 328
      gold: 860
      uniqueCards: 3
      common: 89.894
      rare: 10
      epic: 0.2
      legendary: 0.006
      minRares: 57
    superMagical:
      cards: 738
      gold: 6600
      uniqueCards: 6
      common: 76.570
      rare: 20
      epic: 3.333
      legendary: 0.096
      minRares: 147
      minEpics: 24
    magical:
      cards: 123
      gold: 1200
      uniqueCards: 7
      common: 76.570
      rare: 20
      epic: 3.333
      legendary: 0.096
      minRares: 24
      minEpics: 4
    gold:
      cards: 38
      gold: 1200
      uniqueCards: 4
      common: 76.570
      rare: 20
      epic: 3.333
      legendary: 0.096
      minRares: 4
      minEpics: 0
    silver:
      cards: 12
      gold: 74
      uniqueCards: 2
      common: 76.570
      rare: 20
      epic: 3.333
      legendary: 0.096
      minRares: 1
      minEpics: 0
    epic:
      cards: 20
      gold: 0
      uniqueCards: 4
      common: 0
      rare: 0
      epic: 100
      legendary: 0
      minRares: 0
      minEpics: 20
    legendary:
      cards: 1
      gold: 0
      uniqueCards: 1
      common: 0
      rare: 0
      epic: 0
      legendary: 100
      minRares: 0
      minEpics: 0


class ClashRoyaleCardCtrl
  getAll: ({sort}) ->
    ClashRoyaleCard.getAll({sort, preferCache: true})
    .map EmbedService.embed {embed: defaultEmbed}
    .map ClashRoyaleCard.sanitize null

  getById: ({id}) ->
    ClashRoyaleCard.getById id
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleCard.sanitize null

  getByKey: ({key}) ->
    ClashRoyaleCard.getByKey key
    .then EmbedService.embed {embed: defaultEmbed}
    .then ClashRoyaleCard.sanitize null

  getChestCards: ({arena, chest}) =>
    @getAll({})
    .then (allCards) ->
      allCards = _.filter allCards, (card) ->
        not (card.key in ['golemite', 'lava_pup'])
      allCards = _.groupBy allCards, (card) -> card.data.rarity.toLowerCase()

      chestInfo = chests[arena][chest]
      {common, rare, epic, legendary, cards, gold,
        minRares, minEpics, uniqueCards} = chestInfo

      hasLegendary = Math.random() * 100 < cards * legendary
      cardsLeft = if hasLegendary then cards - 1 else cards
      minRares or= 0
      minEpics or= 0
      rares = Math.min(minRares, cardsLeft * rare)
      epics = Math.min(minEpics, cardsLeft * epic)
      commons = cardsLeft - rares - epics

      counts =
        legendary: if hasLegendary then 1 else 0
        epic: epics
        rare: rares
        common: commons

      uniques = []
      if hasLegendary
        uniques.push 'legendary'
      if epics
        uniques.push 'epic'
      if rares
        uniques.push 'rare'
      if commons
        uniques.push 'common'

      while uniques.length < uniqueCards
        types = ['epic', 'rare', 'common']
        validTypes = _.filter types, (type) ->
          (_.filter(uniques, (t) -> t is type)?.length or 0) < counts[type]
        uniques.push _.sample(validTypes)

      uniquesClone = _.clone uniques
      cardsUsed = []

      chestCards = _.map uniques, (type) ->
        cardsAvailable = counts[type]
        uniqueCardsLeft = _.filter(uniquesClone, (t) -> t is type).length
        if uniqueCardsLeft is 1
          count = cardsAvailable
        else
          multiplier = 2 * Math.random() / uniqueCardsLeft
          count = multiplier * (cardsAvailable - (uniqueCardsLeft - 1))
          count = Math.max(1, Math.floor(count))

        counts[type] -= count
        uniquesClone.splice uniquesClone.indexOf(type), 1

        card = _.sample allCards[type]
        allCards[type] = _.filter allCards[type], ({key}) -> key isnt card.key

        {type, count, card}

      chestCards = _.sortBy chestCards, ({type, count}) ->
        typeValue = 1 / chestInfo[type]
        value = count * typeValue
        value

      if gold
        chestCards.unshift {
          type: 'resource', count: gold, card: {key: 'gold', name: 'Gold'}
        }
      return chestCards


module.exports = new ClashRoyaleCardCtrl()
