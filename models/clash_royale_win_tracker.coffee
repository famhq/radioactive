_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

TWO_WEEKS_S = 3600 * 24 * 14
ONE_WEEK_S = 3600 * 24 * 7
MAX_ROWS_FOR_GROUP = 20000

module.exports = class ClashRoyaleWinTrackerModel
  constructor: ->
    table = @RETHINK_TABLES[0].name
    if table is 'clash_royale_decks'
      @timeFrame = TWO_WEEKS_S
    else
      @timeFrame = ONE_WEEK_S

  getRank: ({thisWeekPopularity, lastWeekPopularity}) =>
    r.table @RETHINK_TABLES[0].name
    .filter(
      r.row(
        if thisWeekPopularity? \
        then 'thisWeekPopularity'
        else 'lastWeekPopularity'
      )
      .gt(
        if thisWeekPopularity? \
        then thisWeekPopularity
        else  lastWeekPopularity
      )
    )
    .count()
    .run()
    .then (rank) -> rank + 1

  updateWinsAndLosses: =>
    Promise.all [
      @getAll {timeFrame: @timeFrame + ONE_WEEK_S, limit: false}
      @getWinsAndLosses()
      @getWinsAndLosses({timeOffset: @timeFrame})
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

  getWins: ({timeOffset}) =>
    r.db('radioactive').table('clash_royale_matches')
    .between(
      r.now().sub(timeOffset + @timeFrame)
      r.now().sub(timeOffset)
      {index: 'time'}
    )
    .limit MAX_ROWS_FOR_GROUP # otherwise group is super slow
    .group('winningDeckId')
    .count()
    .run()
    .map ({group, reduction}) -> {id: group, count: reduction}

  getLosses: ({timeOffset}) =>
    r.db('radioactive').table('clash_royale_matches')
    .between(
      r.now().sub(timeOffset + @timeFrame)
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
  processIncrementById: =>
    states = ['win', 'loss', 'draw']
    _.map states, (state) =>
      subKey = "CLASH_ROYALE_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
      key = CacheService.KEYS[subKey]
      CacheService.arrayGet key
      .then (queue) =>
        CacheService.deleteByKey key
        console.log 'batch deck', queue.length
        if _.isEmpty queue
          return

        queue = _.map queue, JSON.parse
        if state is 'win'
          diff = {
            wins: r.row('wins').add(1)
          }
        else if state is 'loss'
          diff = {
            losses: r.row('losses').add(1)
          }
        else if state is 'draw'
          diff = {
            draws: r.row('draws').add(1)
          }
        else
          diff = {}

        r.table @RETHINK_TABLES[0].name
        .getAll r.args(queue)
        .update diff
        .run()

  incrementById: (id, state, {batch} = {}) =>
    unless id
      console.log 'no id'
      return
    if batch
      subKey = "CLASH_ROYALE_DECK_QUEUED_INCREMENTS_#{state.toUpperCase()}"
      key = CacheService.KEYS[subKey]
      CacheService.arrayAppend key, id
      Promise.resolve null # don't wait
    else
      if state is 'win'
        diff = {
          wins: r.row('wins').add(1)
        }
      else if state is 'loss'
        diff = {
          losses: r.row('losses').add(1)
        }
      else if state is 'draw'
        diff = {
          draws: r.row('draws').add(1)
        }
      else
        diff = {}

      r.table @RETHINK_TABLES[0].name
      .get id
      .update _.defaults diff, {lastUpdateTime: new Date()}
      .run()
