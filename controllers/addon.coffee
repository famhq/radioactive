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

defaultEmbed = [
  EmbedService.TYPES.ADDON.MY_VOTE
]

class AddonCtrl
  getAll: ({language}) ->
    Addon.getAll {language, preferCache: true}
    .then (addons) ->
      _.filter addons, (addon) ->
        not addon.supportedLanguages or language in addon.supportedLanguages
    .map Addon.sanitize null

  getById: ({id}, {user}) ->
    Addon.getById id, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Addon.sanitize null

  getByKey: ({key}, {user}) ->
    Addon.getByKey key, {preferCache: true}
    .then EmbedService.embed {embed: defaultEmbed, user}
    .then Addon.sanitize null

  voteById: ({id, vote}, {user}) ->
    AddonVote.getByCreatorIdAndAddonId user.id, id
    .then (existingVote) ->
      voteNumber = if vote is 'up' then 1 else -1

      hasVotedUp = existingVote?.vote is 1
      hasVotedDown = existingVote?.vote is -1
      if existingVote and voteNumber is existingVote.vote
        router.throw status: 400, info: 'already voted'

      if vote is 'up'
        diff = {upvotes: r.row('upvotes').add(1)}
        if hasVotedDown
          diff.downvotes = r.row('downvotes').sub(1)
          diff.score = r.row('score').add(2)
        else
          diff.score = r.row('score').add(1)
      else if vote is 'down'
        diff = {downvotes: r.row('downvotes').add(1)}
        if hasVotedUp
          diff.upvotes = r.row('upvotes').sub(1)
          diff.score = r.row('score').sub(2)
        else
          diff.score = r.row('score').sub(1)

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
