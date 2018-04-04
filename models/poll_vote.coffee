_ = require 'lodash'

uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
Stream = require './stream'

ONE_DAY_SECONDS = 3600 * 24

defaultPollVote = (pollVote) ->
  unless pollVote?
    return null

  pollVote.value = JSON.stringify pollVote.value

  _.defaults pollVote, {
    id: cknex.getTimeUuid()
  }

defaultPollVoteOutput = (pollVote) ->
  unless pollVote?
    return null

  pollVote.id = "#{pollVote.id}"
  pollVote.userId = "#{pollVote.userId}"
  pollVote.pollId = "#{pollVote.pollId}"
  pollVote.value = try
    JSON.parse pollVote.value
  catch err
    ''
  pollVote

tables = [
  {
    name: 'poll_votes_by_userId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      pollId: 'uuid'
      value: 'text'
    primaryKey:
      # a little uneven since some users will vote a lot, but small data overall
      partitionKey: ['userId']
      clusteringColumns: ['pollId']
  }
  {
    name: 'poll_votes_by_pollId'
    keyspace: 'starfire'
    fields:
      id: 'timeuuid'
      userId: 'uuid'
      pollId: 'uuid'
      value: 'text'
    primaryKey:
      partitionKey: ['pollId']
      clusteringColumns: ['userId']
  }
]

###
TODO: figure out when to reset poll
probably need an admin page where they can reset it...
resetting makes a new poll
###

class PollVoteModel extends Stream
  SCYLLA_TABLES: tables

  constructor: ->
    @streamChannelKey = 'poll_vote'
    @streamChannelsBy = ['pollId']

  upsert: (pollVote, {isUpdate} = {}) ->
    pollVote = defaultPollVote pollVote

    Promise.all [
      cknex().update 'poll_votes_by_userId'
      .set _.omit pollVote, ['userId', 'pollId']
      .where 'userId', '=', pollVote.userId
      .andWhere 'pollId', '=', pollVote.pollId
      .usingTTL ONE_DAY_SECONDS
      .run()

      cknex().update 'poll_votes_by_pollId'
      .set _.omit pollVote, ['userId', 'pollId']
      .where 'userId', '=', pollVote.userId
      .andWhere 'pollId', '=', pollVote.pollId
      .usingTTL ONE_DAY_SECONDS
      .run()
    ]
    .then =>
      pollVote = defaultPollVoteOutput pollVote
      if isUpdate
        @streamUpdateById pollVote.id, pollVote
      else
        @streamCreate pollVote
      pollVote

  getByPollIdAndUserId: (pollId, userId) ->
    cknex().select '*'
    .from 'poll_votes_by_userId'
    .where 'pollId', '=', pollId
    .andWhere 'userId', '=', userId
    .run {isSingle: true}
    .then defaultPollVoteOutput


  getAllByPollId: (pollId, options = {}) =>
    {limit, isStreamed, emit, socket, route,
      initialPostFn, postFn} = options

    initial = cknex().select '*'
    .from 'poll_votes_by_pollId'
    .andWhere 'pollId', '=', pollId
    .run()

    @stream {
      emit
      socket
      route
      initial
      initialPostFn: defaultPollVoteOutput
      postFn: postFn
      channelBy: 'pollId'
      channelById: pollId
    }


module.exports = new PollVoteModel()
