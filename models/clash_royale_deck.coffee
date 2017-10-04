_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

Card = require './clash_royale_card'
CacheService = require '../services/cache'
cknex = require '../services/cknex'
config = require '../config'

# coffeelint: disable=max_line_length
# for naming
TANK_CARD_KEYS = [
  {key: 'giant', name: 'Giant'}
  {key: 'giant_skeleton', name: 'Skelly'}
  {key: 'pekka', name: 'Pekka'}
  {key: 'lava_hound', name: 'Hound'}
  {key: 'golem', name: 'Golem'}
  {key: 'royal_giant', name: 'Royal'}

]
# all spells <= 6 chars
SPELL_CARD_KEYS = [
  {key: 'mirror', name: 'Mirror'}
  {key: 'the_log', name: 'Log'}
  {key: 'zap', name: 'Zap'}
  {key: 'poison', name: 'Poison'}
  {key: 'rocket', name: 'Rocket'}
  {key: 'rage', name: 'Rage'}
  {key: 'goblin_barrel', name: 'Goblin'}
  {key: 'arrows', name: 'Arrows'}
  {key: 'freeze', name: 'Freeze'}
]
ADJECTIVES = [
  'legal', 'unnatural', 'dependent', 'cold', 'normal', 'sour', 'fresh', 'pointless', 'lavish', 'elated', 'imminent', 'natural', 'unruly', 'venomous', 'flat', 'prickly', 'fragile', 'ahead', 'elite', 'astonishing', 'eager', 'obsolete', 'white', 'mysterious', 'sick', 'wide', 'interesting', 'unsightly', 'evasive', 'trashy', 'meaty', 'greedy', 'merciful', 'futuristic', 'unique', 'adjoining', 'juvenile', 'coherent', 'heady', 'hollow', 'incredible', 'tense', 'gentle', 'political', 'odd', 'auspicious', 'daffy', 'abhorrent', 'agreeable', 'callous', 'cut', 'mighty', 'milky', 'quaint', 'determined', 'deranged', 'satisfying', 'confused', 'purple', 'habitual', 'cumbersome', 'loud', 'thundering', 'useless', 'thoughtless', 'hesitant', 'salty', 'spotty', 'faulty', 'trite', 'sweet', 'worthless', 'internal', 'insidious', 'broken', 'homely', 'gaping', 'dispensable', 'cool', 'faded', 'far-flung', 'childlike', 'reflective', 'vengeful', 'smoggy', 'fast', 'statuesque', 'fine', 'black', 'stereotyped', 'aberrant', 'abiding', 'exultant', 'synonymous', 'rustic', 'resonant', 'impolite', 'swift', 'raspy', 'small', 'five', 'burly', 'cowardly', 'jumbled', 'rhetorical', 'tense', 'harsh', 'disagreeable', 'nostalgic', 'puzzling', 'well-groomed', 'husky', 'ethereal', 'unbecoming', 'defective', 'previous', 'green', 'concerned', 'married', 'dull', 'unused', 'overrated', 'grubby', 'excited', 'dangerous', 'striped', 'onerous', 'erect', 'devilish', 'acrid', 'overt', 'oceanic', 'right', 'needless', 'scintillating', 'nosy', 'hulking', 'enthusiastic', 'profuse', 'giddy', 'terrible', 'lame', 'lean', 'shiny', 'stiff', 'super', 'deafening', 'invincible', 'proud', 'hellish', 'hypnotic', 'abstracted', 'terrific', 'empty', 'beneficial', 'torpid', 'melted', 'macabre', 'guttural', 'flimsy', 'resolute', 'gleaming', 'ill', 'rotten', 'blue-eyed', 'quick', 'yummy', 'dynamic', 'funny', 'loose', 'assorted', 'adaptable', 'glistening', 'boorish', 'sad', 'mountainous', 'misty', 'stingy', 'grouchy', 'taboo', 'third', 'acceptable', 'orange', 'comfortable', 'ordinary', 'moldy', 'open', 'vast', 'absent', 'spectacular', 'enchanted', 'even', 'vigorous', 'uptight', 'historical', 'scientific'
  'able', 'amazing', 'deft', 'dull', 'eager', 'idle', 'nasty', 'noisy', 'quick', 'slow', 'ugly', 'sad', 'sassy', 'unstable', 'stable', 'playful', 'lean', 'lazy', 'lame', 'lovable', 'gloomy', 'cruel', 'clever', 'clean', 'sour', 'sleepy', 'testy', 'tired', 'timid', 'direct', 'dreary', 'energetic', 'intelligent', 'bright', 'brave', 'blue'
]
MAX_RANDOM_NAME_ATTEMPTS = 30
# coffeelint: enable=max_line_length

tables = [
  {
    name: 'counter_by_deckId'
    fields:
      deckId: 'text'
      gameType: 'text'
      arena: 'int'
      wins: 'counter'
      losses: 'counter'
      draws: 'counter'
    primaryKey:
      partitionKey: ['deckId']
      clusteringColumns: ['gameType', 'arena']
  }
  {
    name: 'counter_by_deckId_opponentCardId'
    fields:
      deckId: 'text'
      opponentCardId: 'text'
      gameType: 'text'
      arena: 'int'
      wins: 'counter'
      losses: 'counter'
      draws: 'counter'
    primaryKey:
      partitionKey: ['deckId']
      # might not need opponentCardId in here
      clusteringColumns: ['gameType', 'arena', 'opponentCardId']
  }
]

defaultClashRoyaleDeck = (clashRoyaleDeck) ->
  unless clashRoyaleDeck?
    return null

  _.defaults {
    arena: parseInt clashRoyaleDeck.arena
    wins: parseInt clashRoyaleDeck.wins
    losses: parseInt clashRoyaleDeck.losses
    draws: parseInt clashRoyaleDeck.draws
  }, clashRoyaleDeck

class ClashRoyaleDeckModel
  SCYLLA_TABLES: tables

  batchUpsertByMatches: (matches) ->
    deckIdCnt = {}
    deckIdCardIdCnt = {}

    mapDeckCondition = (condition, deckIds, opponentCardIds, gameType, arena) ->
      _.forEach deckIds, (deckId) ->
        deckKey = [deckId, gameType, arena].join(',')
        allDeckKey = [deckId, 'all', 0].join(',')
        deckIdCnt[deckKey] ?= {wins: 0, losses: 0, draws: 0}
        deckIdCnt[deckKey][condition] += 1
        deckIdCnt[allDeckKey] ?= {wins: 0, losses: 0, draws: 0}
        deckIdCnt[allDeckKey][condition] += 1
        _.forEach opponentCardIds, (cardId) ->
          key = [deckId, gameType, arena, cardId].join(',')
          allKey = [deckId, 'all', 0, cardId].join(',')
          deckIdCardIdCnt[key] ?= {wins: 0, losses: 0, draws: 0}
          deckIdCardIdCnt[key][condition] += 1
          deckIdCardIdCnt[allKey] ?= {wins: 0, losses: 0, draws: 0}
          deckIdCardIdCnt[allKey][condition] += 1

    _.forEach matches, (match) ->
      gameType = match.type
      if config.DECK_TRACKED_GAME_TYPES.indexOf(gameType) is -1
        return
      arena = if gameType is 'PvP' then match.arena else 0
      mapDeckCondition(
        'wins', match.winningDeckIds, match.losingCardIds, gameType, arena
      )
      mapDeckCondition(
        'losses', match.losingDeckIds, match.winningCardIds, gameType, arena
      )
      mapDeckCondition(
        'draws', match.drawDeckIds, match.drawCardIds, gameType, arena
      )

    deckIdQueries = _.map deckIdCnt, (diff, key) ->
      [deckId, gameType, arena] = key.split ','
      q = cknex().update 'counter_by_deckId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'deckId', '=', deckId
      .andWhere 'gameType', '=', gameType
      .andWhere 'arena', '=', arena

    deckIdCardIdQueries = _.map deckIdCardIdCnt, (diff, key) ->
      [deckId, gameType, arena, cardId] = key.split ','
      diff = _.pickBy diff
      q = cknex().update 'counter_by_deckId_opponentCardId'
      _.forEach diff, (amount, key) ->
        q = q.increment key, amount
      q.where 'deckId', '=', deckId
      .andWhere 'gameType', '=', gameType
      .andWhere 'arena', '=', arena
      .andWhere 'opponentCardId', '=', cardId

    Promise.all [
      # batch is faster, but can't exceed 50kb
      cknex.batchRun deckIdQueries
      # cknex.batchRun deckIdCardIdQueries
    ]

  # getRandomName: (cards, attempts = 0) =>
  #   cardKeys = _.map(cards, 'key')
  #   tankKeys = _.map(TANK_CARD_KEYS, 'key')
  #   spellKeys = _.map(SPELL_CARD_KEYS, 'key')
  #   tankKey = _.sample _.intersection(cardKeys, tankKeys)
  #   spellKey = _.sample _.intersection(cardKeys, spellKeys)
  #   tankName = _.find(TANK_CARD_KEYS, {key: tankKey})?.name
  #   spellName = _.find(SPELL_CARD_KEYS, {key: spellKey})?.name
  #   name = "#{_.startCase _.sample ADJECTIVES}" +
  #           (if tankName then " #{tankName}" else '') +
  #           (if spellName then " #{spellName}" else '')
  #
  #   return @getByName name
  #   .then (deck) =>
  #     if deck and attempts < MAX_RANDOM_NAME_ATTEMPTS
  #       # console.log 'dupe name', name, attempts
  #       @getRandomName cards, attempts + 1
  #     else if deck
  #       'Nameless'
  #     else
  #       name

  getById: (id) ->
    cknex().select '*'
    .where 'deckId', '=', id
    .andWhere 'gameType', '=', 'all'
    .from 'counter_by_deckId'
    .run {isSingle: true}
    .then defaultClashRoyaleDeck

  getAllByIds: (ids) ->
    cknex().select '*'
    .where 'deckId', 'in', id
    .andWhere 'gameType', '=', 'all'
    .from 'counter_by_deckId'
    .run()
    .map defaultClashRoyaleDeck

  getDeckId: (cardKeys) ->
    cardKeys = _.sortBy(cardKeys).join '|'

  sanitize: _.curry (requesterId, clashRoyaleDeck) ->
    _.pick clashRoyaleDeck, [
      'deckId'
      'cards'
      'averageElixirCost'
      'wins'
      'losses'
      'draws'
    ]

  # TODO: different sanitization for API
  sanitizeLite: _.curry (requesterId, clashRoyaleDeck) ->
    clashRoyaleDeck = _.pick clashRoyaleDeck, [
      'deckId'
      'cards' # req for decks tab on profile
      'averageElixirCost'
      'wins'
      'losses'
      'draws'
    ]
    clashRoyaleDeck.cards = _.omit clashRoyaleDeck, ['data']
    clashRoyaleDeck

module.exports = new ClashRoyaleDeckModel()
