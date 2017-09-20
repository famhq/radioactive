_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
Addon = require '../models/addon'
AddonVote = require '../models/addon_vote'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
r = require '../services/rethinkdb'
schemas = require '../schemas'
config = require '../config'

class AddonCtrl
  voteById: ({id, vote}, {user}) ->
    Promise.all [
      Addon.getById id
      AddonVote.getByCreatorIdAndParent user.id, id, 'thread'
    ]
    .then ([thread, existingVote]) ->
      voteNumber = if vote is 'up' then 1 else -1

      hasVotedUp = existingVote?.vote is 1
      hasVotedDown = existingVote?.vote is -1
      if existingVote and voteNumber is existingVote.vote
        router.throw status: 400, info: 'already voted'

      if vote is 'up'
        diff = {upvotes: r.row('upvotes').add(1)}
        if hasVotedDown
          diff.downvotes = r.row('downvotes').sub(1)
      else if vote is 'down'
        diff = {downvotes: r.row('downvotes').add(1)}
        if hasVotedUp
          diff.upvotes = r.row('upvotes').sub(1)

      Promise.all [
        if existingVote
          AddonVote.updateById existingVote.id, {vote: voteNumber}
        else
          AddonVote.create {
            creatorId: user.id
            addonId: id
            vote: voteNumber
          }

        Addon.updateById id, diff
      ]

module.exports = new AddonCtrl()
