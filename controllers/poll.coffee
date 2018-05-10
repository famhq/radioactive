_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
Poll = require '../models/poll'
Group = require '../models/group'
PollVote = require '../models/poll_vote'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
r = require '../services/rethinkdb'
schemas = require '../schemas'
config = require '../config'

defaultEmbed = [
  # EmbedService.TYPES.POLL.MY_VOTE
]

class PollCtrl
  getById: ({id}, {user}) ->
    Poll.getById id, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed, user}

  resetById: ({id}, {user}) ->
    Promise.all [
      Poll.getById id, {preferCache: true}
      PollVote.getCountByPollId id
    ]
    .then ([poll, pollVoteCount]) ->
      pollVoteCount ?= 0

      Promise.all [
        Poll.deleteByPoll poll
        Poll.upsert {
          groupId: poll.groupId
          data:
            heatMapMax: parseInt(pollVoteCount / 15) or 1
        }
      ]
    # PollVote.getAllByPollId id
    # .map PollVote.deleteByPollVote

  getAllByGroupId: ({groupId}, {user}, {emit, socket, route}) ->
    Poll.getAllByGroupId groupId, {
      isStreamed: true
      emit: emit
      socket: socket
      route: route
    }
    .then (polls) ->
      if _.isEmpty polls
        Poll.upsert {groupId}
        .then (poll) -> [poll]
      else
        polls
    # .map EmbedService.embed {embed: defaultEmbed, user}

  getAllVotesById: ({id}, {user}, {emit, socket, route}) ->
    PollVote.getAllByPollId id, {
      isStreamed: true
      emit: emit
      socket: socket
      route: route
    }
    # .map EmbedService.embed {embed: defaultEmbed, user}

  voteById: ({id, value}, {user}) ->
    Promise.all [
      Poll.getById id
      PollVote.getByPollIdAndUserId id, user.id
    ]
    .then ([poll, existingVote]) ->
      console.log 'vote', existingVote?.id
      PollVote.upsert(
        {id: existingVote?.id, userId: user.id, pollId: id, value}
        {isUpdate: Boolean existingVote}
      )

module.exports = new PollCtrl()
