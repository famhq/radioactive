_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

ClashRoyaleWinTrackerModel = require './clash_royale_win_tracker'
Card = require './clash_royale_card'
CacheService = require '../services/cache'
r = require '../services/rethinkdb'
config = require '../config'

CLASH_ROYALE_DECK_TABLE = 'clash_royale_decks'
ADD_TIME_INDEX = 'addTime'
POPULARITY_INDEX = 'thisWeekPopularity'
CARD_IDS_INDEX = 'cardIds'
NAME_INDEX = 'name'
ONE_WEEK_S = 3600 * 24 * 7
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

defaultClashRoyaleDeck = (clashRoyaleDeck) ->
  unless clashRoyaleDeck?
    return null

  _.defaults clashRoyaleDeck, {
    # all card keys alphabetized and joined with `|`
    id: clashRoyaleDeck?.cardKeys
    name: null
    cardIds: []
    wins: 0
    losses: 0
    draws: 0
    createdByUserId: null
    addTime: new Date()
    lastUpdateTime: new Date()
  }

class ClashRoyaleDeckModel extends ClashRoyaleWinTrackerModel
  RETHINK_TABLES: [
    {
      name: CLASH_ROYALE_DECK_TABLE
      options: {}
      indexes: [
        {name: ADD_TIME_INDEX}
        {name: NAME_INDEX}
        {name: CARD_IDS_INDEX, options: {multi: true}}
        {name: POPULARITY_INDEX}
      ]
    }
  ]

  batchCreate: (clashRoyaleDecks) ->
    clashRoyaleDecks = _.map clashRoyaleDecks, defaultClashRoyaleDeck

    r.table CLASH_ROYALE_DECK_TABLE
    .insert clashRoyaleDecks
    .run()

  create: (clashRoyaleDeck, {durability, skipWait} = {}) ->
    clashRoyaleDeck = defaultClashRoyaleDeck clashRoyaleDeck
    durability ?= 'hard'

    query = r.table CLASH_ROYALE_DECK_TABLE
    .insert clashRoyaleDeck, {durability}
    .run()
    .then ->
      clashRoyaleDeck

    if skipWait
      clashRoyaleDeck
    else
      query

  getRandomName: (cards, attempts = 0) =>
    cardKeys = _.map(cards, 'key')
    tankKeys = _.map(TANK_CARD_KEYS, 'key')
    spellKeys = _.map(SPELL_CARD_KEYS, 'key')
    tankKey = _.sample _.intersection(cardKeys, tankKeys)
    spellKey = _.sample _.intersection(cardKeys, spellKeys)
    tankName = _.find(TANK_CARD_KEYS, {key: tankKey})?.name
    spellName = _.find(SPELL_CARD_KEYS, {key: spellKey})?.name
    name = "#{_.startCase _.sample ADJECTIVES}" +
            (if tankName then " #{tankName}" else '') +
            (if spellName then " #{spellName}" else '')

    return @getByName name
    .then (deck) =>
      if deck and attempts < MAX_RANDOM_NAME_ATTEMPTS
        # console.log 'dupe name', name, attempts
        @getRandomName cards, attempts + 1
      else if deck
        'Nameless'
      else
        name

  getByName: (name) ->
    r.table CLASH_ROYALE_DECK_TABLE
    .getAll name, {index: 'name'}
    .nth 0
    .default null
    .run()
    .then defaultClashRoyaleDeck

  getById: (id) ->
    r.table CLASH_ROYALE_DECK_TABLE
    .get id
    .run()
    .then defaultClashRoyaleDeck

  getByIds: (ids) ->
    r.table CLASH_ROYALE_DECK_TABLE
    .getAll ids...
    .run()
    .map defaultClashRoyaleDeck

  getCardKeys: (cards) ->
    cardKeys = _.sortBy(cards).join '|'

  getByCardKeys: (cardKeys, {preferCache, cards} = {}) =>
    cardKeysStr = @getCardKeys cardKeys
    get = =>
      start2 = Date.now()
      r.table CLASH_ROYALE_DECK_TABLE
      .get cardKeysStr
      .run()
      .then (deck) =>
        if deck
          return deck
        else
          Promise.all [
            # too slow...
            # @getRandomName(_.map(cardKeys, (key) -> {key}))
            Promise.resolve 'Nameless'
            Promise.map cardKeys, (key) ->
              _.find(cards, {key}) or  Card.getByKey(key, {preferCache})
          ]
          .then ([randomName, cards]) =>
            @create {
              cardKeys: cardKeysStr
              name: randomName
              cardIds: _.filter _.map(cards, 'id')
            }, {skipWait: true}
      .then defaultClashRoyaleDeck
    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_DECK_CARD_KEYS
      key = "#{prefix}:#{cardKeysStr}"
      CacheService.preferCache key, get, {expireSeconds: ONE_WEEK_S}
    else
      get()

  getAll: ({limit, sort, timeFrame} = {}) ->
    limit ?= 10

    sortQ = if sort is 'recent' \
            then {index: r.desc(ADD_TIME_INDEX)}
            else if sort is 'popular'
            then {index: r.desc(POPULARITY_INDEX)}
            else POPULARITY_INDEX

    q = r.table CLASH_ROYALE_DECK_TABLE
    if timeFrame
      q = q.filter r.row('lastUpdateTime').gt(timeFrame)

    q = q.orderBy sortQ
    if limit
      q = q.limit limit
    q.run()
    .map defaultClashRoyaleDeck

  updateById: (id, diff) ->
    r.table CLASH_ROYALE_DECK_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table CLASH_ROYALE_DECK_TABLE
    .get id
    .delete()
    .run()

  sanitize: _.curry (requesterId, clashRoyaleDeck) ->
    _.pick clashRoyaleDeck, [
      'id'
      'name'
      'cardIds'
      'cards'
      'averageElixirCost'
      'thisWeekPopularity'
      'timeRanges'
      'wins'
      'losses'
      'draws'
      'addTime'
    ]

module.exports = new ClashRoyaleDeckModel()
