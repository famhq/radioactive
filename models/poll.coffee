_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
Stream = require './stream'
config = require '../config'

SIX_HOURS_S = 3600 * 6

defaultPoll = (poll) ->
  unless poll?
    return null

  poll.data = JSON.stringify poll.data

  _.defaults {
    id: uuid.v4()
    name: ''
  }, poll

defaultPollOutput = (poll) ->
  unless poll?
    return null

  if poll.data
    poll.data = try
      JSON.parse poll.data
    catch err
      {}

  poll

class PollModel extends Stream
  TABLE_NAME: 'polls_by_id'

  constructor: ->
    @streamChannelKey = 'poll'
    @streamChannelsBy = ['groupId']

    @SCYLLA_TABLES = [
      {
        name: 'polls_by_id'
        keyspace: 'starfire'
        fields:
          id: 'uuid'
          groupId: 'uuid'
          name: 'text'
          data: 'text' # betAmount, betCurrency
                       # should typically be 100 currency
        primaryKey:
          partitionKey: ['id']
          clusteringColumns: null
      }
      # if the value is 100% correct, they get share of the pot
      # pot is everything others bet combined

      # if no one gets it, pot continues to next round
      {
        name: 'polls_wager_counter'
        keyspace: 'starfire'
        fields:
          id: 'uuid'
          pot: 'counter'
        primaryKey:
          partitionKey: ['id']
          clusteringColumns: null
      }
      {
        name: 'polls_by_groupId'
        keyspace: 'starfire'
        fields:
          id: 'uuid'
          groupId: 'uuid'
          name: 'text'
          data: 'text'
        primaryKey:
          partitionKey: ['groupId']
          clusteringColumns: ['id']
      }
    ]

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex('starfire').select '*'
      .where 'id', '=', id
      .from 'polls_by_id'
      .run {isSingle: true}
      # .then defaultPollOutput

    if false # TODO
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByGroupId: (groupId, options = {}) =>
    {limit, isStreamed, emit, socket, route,
      initialPostFn, postFn} = options

    initial = cknex('starfire').select '*'
    .where 'groupId', '=', groupId
    .from 'polls_by_groupId'
    .limit 50
    .run()

    @stream {
      emit
      socket
      route
      initial
      # initialPostFn: defaultPollVoteOutput
      postFn: postFn
      channelBy: 'groupId'
      channelById: groupId
    }

  deleteByPoll: (poll) ->
    Promise.all [
      cknex('starfire').delete()
      .from 'polls_by_id'
      .where 'id', '=', poll.id
      .run()

      cknex('starfire').delete()
      .from 'polls_by_groupId'
      .where 'groupId', '=', poll.groupId
      .andWhere 'id', '=', poll.id
      .run()
    ]
    .tap =>
      @streamDeleteById poll.id, poll

  upsert: (poll, {isUpdate} = {}) ->
    poll = defaultPoll poll

    Promise.all [
      cknex('starfire').update 'polls_by_id'
      .set _.omit poll, ['id']
      .where 'id', '=', poll.id
      .run()

      cknex('starfire').update 'polls_by_groupId'
      .set _.omit poll, ['groupId', 'id']
      .where 'groupId', '=', poll.groupId
      .andWhere 'id', '=', poll.id
      .run()
    ]
    .then =>
      # poll = defaultPollOutput poll
      if isUpdate
        @streamUpdateById poll.id, poll
      else
        @streamCreate poll
      poll


module.exports = new PollModel()
