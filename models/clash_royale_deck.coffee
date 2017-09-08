_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

Card = require './clash_royale_card'
CacheService = require '../services/cache'
r = require '../services/rethinkdb'
knex = require '../services/knex'
config = require '../config'

CLASH_ROYALE_DECK_TABLE = 'clash_royale_decks'
POSTGRES_DECKS_TABLE = 'decks'
ADD_TIME_INDEX = 'addTime'
POPULARITY_INDEX = 'thisWeekPopularity'
CARD_IDS_INDEX = 'cardIds'
NAME_INDEX = 'name'
SIX_HOURS_S = 3600 * 6
TWO_WEEKS_S = 3600 * 24 * 14
MAX_ROWS_FOR_GROUP = 20000

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

fields = [
  {name: 'id', type: 'string', length: 150, index: 'primary'}
  {name: 'name', type: 'string', index: 'default'}
  # {name: 'type', type: 'string'}
  {name: 'cardIds', type: 'array', arrayType: 'varchar', index: 'gin'}
  {name: 'wins', type: 'integer', defaultValue: 0}
  {name: 'losses', type: 'integer', defaultValue: 0}
  {name: 'draws', type: 'integer', defaultValue: 0}
  {name: 'popularity', type: 'integer', defaultValue: 0, index: 'default'}
  {
    name: 'thisWeekPopularity', type: 'integer'
    defaultValue: 0, index: 'default'
  }
  {name: 'createdByUserId', type: 'uuid'}
  {
    name: 'addTime', type: 'dateTime'
    defaultValue: new Date(), index: 'default'
  }
  {name: 'lastUpdateTime', type: 'dateTime', defaultValue: new Date()}
]

defaultClashRoyaleDeck = (clashRoyaleDeck) ->
  unless clashRoyaleDeck?
    return null

  clashRoyaleDeck?.id ?= clashRoyaleDeck?.cardKeys

  _.defaults clashRoyaleDeck, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

class ClashRoyaleDeckModel
  POSTGRES_TABLES: [
    {
      tableName: POSTGRES_DECKS_TABLE
      fields: fields
      indexes: [
        # {columns: ['popularity', 'type']}
      ]
    }
  ]

  batchCreate: (clashRoyaleDecks) ->
    clashRoyaleDecks = _.map clashRoyaleDecks, defaultClashRoyaleDeck

    knex.insert(clashRoyaleDecks).into(POSTGRES_DECKS_TABLE)
    .catch (err) ->
      console.log 'postgres err', err

  create: (clashRoyaleDeck, {durability} = {}) ->
    clashRoyaleDeck = defaultClashRoyaleDeck clashRoyaleDeck
    durability ?= 'hard'

    clashRoyaleDeck = _.pick clashRoyaleDeck, _.map(fields, 'name')

    knex.insert(clashRoyaleDeck).into(POSTGRES_DECKS_TABLE)
    .then ->
      clashRoyaleDeck


  # getRank: ({thisWeekPopularity, lastWeekPopularity}) =>
  #   r.table @RETHINK_TABLES[0].name
  #   .filter(
  #     r.row(
  #       if thisWeekPopularity? \
  #       then 'thisWeekPopularity'
  #       else 'lastWeekPopularity'
  #     )
  #     .gt(
  #       if thisWeekPopularity? \
  #       then thisWeekPopularity
  #       else  lastWeekPopularity
  #     )
  #   )
  #   .count()
  #   .run()
  #   .then (rank) -> rank + 1

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
    knex POSTGRES_DECKS_TABLE
    .first '*'
    .where {name}
    .then defaultClashRoyaleDeck

  getById: (id) ->
    knex.table POSTGRES_DECKS_TABLE
    .first '*'
    .where {id}
    .then defaultClashRoyaleDeck

  getAllByIds: (ids) ->
    knex POSTGRES_DECKS_TABLE
    .select '*'
    .whereIn 'id', ids
    .map defaultClashRoyaleDeck

  getDeckId: (cardKeys) ->
    cardKeys = _.sortBy(cardKeys).join '|'

  getByCardKeys: (cardKeys, {preferCache, cards} = {}) =>
    cardKeysStr = @getDeckId cardKeys
    get = =>
      @getById cardKeys
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
              id: cardKeysStr
              name: randomName
              cardIds: _.filter _.map(cards, 'id')
            }
      .then defaultClashRoyaleDeck
    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_DECK_CARD_KEYS
      key = "#{prefix}:#{cardKeysStr}"
      CacheService.preferCache key, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  # TODO
  getAll: ({limit, sort, timeFrame} = {}) ->
    limit ?= 10

    sortColumn = if sort is 'recent' then ADD_TIME_INDEX else POPULARITY_INDEX
    q = knex POSTGRES_DECKS_TABLE
    .select '*'
    if timeFrame
      q = q.where 'lastUpdateTime', '>', timeFrame
    q.orderBy sortColumn, 'desc'
    .limit limit
    .map defaultClashRoyaleDeck

  updateWinsAndLosses: =>
    Promise.all [
      @getAll {timeFrame: TWO_WEEKS_S + ONE_WEEK_S, limit: false}
      @getWinsAndLosses()
      @getWinsAndLosses({timeOffset: TWO_WEEKS_S})
    ]
    .then ([items, thisWeek, lastWeek]) =>
      Promise.map items, (item) =>
        thisWeekItem = _.find thisWeek, {id: item.id}
        lastWeekItem = _.find lastWeek, {id: item.id}
        thisWeekWins = thisWeekItem?.wins or 0
        thisWeekLosses = thisWeekItem?.losses or 0
        thisWeekPopularity = thisWeekWins + thisWeekLosses
        lastWeekWins = lastWeekItem?.wins or 0
        lastWeekLosses = lastWeekItem?.losses or 0
        lastWeekPopularity = lastWeekWins + lastWeekLosses

        @updateById item.id, {
          thisWeekPopularity: thisWeekPopularity
          lastWeekPopularity: lastWeekPopularity
          timeRanges:
            thisWeek:
              thisWeekPopularity: thisWeekPopularity
              verifiedWins: thisWeekWins
              verifiedLosses: thisWeekLosses
            lastWeek:
              lastWeekPopularity: lastWeekPopularity
              verifiedWins: lastWeekWins
              verifiedLosses: lastWeekLosses
        }
        .then ->
          {id: item.id, thisWeekPopularity, lastWeekPopularity}
      , {concurrency: 10}
      # FIXME: this is *insanely* slow for decks on prod
      # .then (updates) =>
      #   Promise.map items, ({id}) =>
      #     {thisWeekPopularity, lastWeekPopularity} = _.find updates, {id}
      #     Promise.all [
      #       @getRank {thisWeekPopularity}
      #       @getRank {lastWeekPopularity}
      #     ]
      #     .then ([thisWeekRank, lastWeekRank]) =>
      #       @updateById id,
      #         timeRanges:
      #           thisWeek:
      #             rank: thisWeekRank
      #           lastWeek:
      #             rank: lastWeekRank
      #   , {concurrency: 10}

  getWinsAndLosses: ({timeOffset} = {}) =>
    timeOffset ?= 0
    Promise.all [@getWins({timeOffset}), @getLosses({timeOffset})]
    .then ([wins, losses]) ->
      Promise.map wins, ({id, count}) ->
        {id, wins: count, losses: _.find(losses, {id})?.count}

  getWins: ({timeOffset}) ->
    knex 'clash_royale_matches'
    .select '*'
    .where 'time', '>', Date.now().sub ((timeOffset + TWO_WEEKS_S) * 1000)
    .andWhere 'time', '<', Date.now().sub ((timeOffset) * 1000)
    .limit MAX_ROWS_FOR_GROUP # otherwise group is super slow?
    .groupBy('winningDeckId')
    .map defaultClashRoyaleDeck

  getLosses: ({timeOffset}) ->
    r.db('radioactive').table('clash_royale_matches')
    .between(
      r.now().sub(timeOffset + TWO_WEEKS_S)
      r.now().sub(timeOffset)
      {index: 'time'}
    )
    .limit MAX_ROWS_FOR_GROUP
    .group('losingDeckId')
    .count()
    .run()
    .map ({group, reduction}) -> {id: group, count: reduction}


  # the fact that this actually works is a little peculiar. technically, it
  # should only increment a batched deck by max of 1, but getAll
  # for multiple of same id grabs the same id multiple times (and updates).
  # TODO: group by count, separate query to .add(count)
  # FIXME FIXME: rm, doesn't work with postgres
  # processIncrementById: =>
  #   states = ['win', 'loss', 'draw']
  #   _.map states, (state) =>
  #     subKey = "CLASH_ROYALE_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
  #     key = CacheService.KEYS[subKey]
  #     CacheService.arrayGet key
  #     .then (queue) =>
  #       CacheService.deleteByKey key
  #       console.log 'batch deck', queue.length
  #       if _.isEmpty queue
  #         return
  #
  #       queue = _.map queue, JSON.parse
  #       if state is 'win'
  #         diff = {
  #           wins: r.row('wins').add(1)
  #         }
  #       else if state is 'loss'
  #         diff = {
  #           losses: r.row('losses').add(1)
  #         }
  #       else if state is 'draw'
  #         diff = {
  #           draws: r.row('draws').add(1)
  #         }
  #       else
  #         diff = {}
  #
  #       r.table @RETHINK_TABLES[0].name
  #       .getAll r.args(queue)
  #       .update diff
  #       .run()
  #
  incrementAllByIds: (ids, changes) ->
    knex POSTGRES_DECKS_TABLE
    .whereIn 'id', ids
    .update _.mapValues changes, (increment, key) ->
      unless key in ['wins', 'losses', 'draws']
        throw new Error 'invalid key'
      if isNaN increment
        throw new Error 'invalid increment'
      knex.raw "\"#{key}\" + #{increment}"

  updateById: (id, diff) ->
    knex POSTGRES_DECKS_TABLE
    .where {id}
    .update diff

  deleteById: (id) ->
    knex POSTGRES_DECKS_TABLE
    .where {id}
    .limit 1
    .del()

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

  # TODO: different sanitization for API
  sanitizeLite: _.curry (requesterId, clashRoyaleDeck) ->
    _.pick clashRoyaleDeck, [
      'cardIds'
      'cards' # req for decks tab on profile
      'averageElixirCost'
      'wins'
      'losses'
      'draws'
      'addTime'
    ]

module.exports = new ClashRoyaleDeckModel()
