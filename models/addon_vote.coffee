_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'
CacheService = require '../services/cache'

defaultAddonVote = (addonVote) ->
  unless addonVote?
    return null

  id = "#{addonVote.addonId}:#{addonVote.creatorId}"

  _.defaults addonVote, {
    id: id
    creatorId: null
    addonId: null
    vote: 0 # -1 or 1
    time: new Date()
  }

THREAD_VOTES_TABLE = 'addon_votes'
CREATOR_ID_ADDON_ID_INDEX = 'creatorIdAddonId'
MAX_MESSAGES = 30

class AddonVoteModel
  RETHINK_TABLES: [
    {
      name: THREAD_VOTES_TABLE
      indexes: [
        {name: CREATOR_ID_ADDON_ID_INDEX, fn: (row) ->
          [row('creatorId'), row('addonId')]}
      ]
    }
  ]

  create: (addonVote) ->
    addonVote = defaultAddonVote addonVote

    r.table THREAD_VOTES_TABLE
    .insert addonVote
    .run()
    .then ->
      addonVote

  updateById: (id, diff) ->
    r.table THREAD_VOTES_TABLE
    .get id
    .update diff
    .run()

  getByCreatorIdAndAddonId: (creatorId, addonId) ->
    r.table THREAD_VOTES_TABLE
    .getAll [creatorId, addonId], {
      index: CREATOR_ID_ADDON_ID_INDEX
    }
    .nth 0
    .default null
    .run()
    .then defaultAddonVote

  getById: (id) ->
    r.table THREAD_VOTES_TABLE
    .get id
    .run()
    .then defaultAddonVote

module.exports = new AddonVoteModel()
