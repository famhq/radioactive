_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'

User = require '../models/user'
Addon = require '../models/addon'
Group = require '../models/group'
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
  getAllByGroupId: ({groupId}) ->
    Group.getById groupId, {preferCache: true}
    .then (group) ->
      gameKeys = if _.isEmpty(group.gameKeys) \
                 then ['clash-royale']
                 else group.gameKeys
      Promise.map gameKeys or ['clash-royale'], (gameKey) ->
        Addon.getAllByGameKey gameKey, {preferCache: true}
      .then (addons) ->
        addons = _.flatten addons
        language = group.language
        _.filter addons, (addon) ->
          not addon.data.supportedLanguages or
            language in addon.data.supportedLanguages
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
    Promise.all [
      Addon.getById id
      AddonVote.getByCreatorIdAndAddonId user.id, id
    ]
    .then ([addon, existingVote]) ->
      voteNumber = if vote is 'up' then 1 else -1

      hasVotedUp = existingVote?.vote is 1
      hasVotedDown = existingVote?.vote is -1
      if existingVote and voteNumber is existingVote.vote
        router.throw status: 400, info: 'already voted'

      if vote is 'up'
        values = {upvotes: 1}
        if hasVotedDown
          values.downvotes = -1
      else if vote is 'down'
        values = {downvotes: 1}
        if hasVotedUp
          values.upvotes = -1

      voteTime = existingVote?.time or new Date()

      Promise.all [
        AddonVote.upsertByCreatorIdAndAddonId(
          user.id, id, {vote: voteNumber}
        )

        Addon.incrementByAddon addon, values
      ]

module.exports = new AddonCtrl()
