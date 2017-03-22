_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

TWO_WEEKS_S = 3600 * 24 * 14
ONE_WEEK_S = 3600 * 24 * 7

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
    .group('winningDeckId')
    .count()
    .run()
    .map ({group, reduction}) -> {id: group, count: reduction}

  incrementById: (id, state) =>
    unless id
      console.log 'no id'
      return
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
