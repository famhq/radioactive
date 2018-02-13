_ = require 'lodash'

uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

DEFAULT_UUID = '00000000-0000-0000-0000-000000000000'

defaultAddonVote = (addonVote) ->
  unless addonVote?
    return null

  _.defaults addonVote, {
    vote: 0 # -1 or 1
    time: new Date()
  }

# with this structure we'd need another table to get votes by addonId
tables = [
  {
    name: 'addon_votes_by_creatorId'
    keyspace: 'starfire'
    fields:
      creatorId: 'uuid'
      addonId: 'uuid'
      vote: 'int'
      time: 'timestamp'
    primaryKey:
      # a little uneven since some users will vote a lot, but small data overall
      partitionKey: ['creatorId']
      clusteringColumns: ['addonId']
  }
]

class AddonVoteModel
  SCYLLA_TABLES: tables

  upsertByCreatorIdAndAddonId: (creatorId, addonId, addonVote) ->
    addonVote = defaultAddonVote addonVote

    cknex().update 'addon_votes_by_creatorId'
    .set addonVote
    .where 'creatorId', '=', creatorId
    .andWhere 'addonId', '=', addonId
    .run()
    .then ->
      addonVote

  getByCreatorIdAndAddonId: (creatorId, addonId) ->
    unless creatorId and addonId and addonId isnt 'undefined'
      return Promise.resolve null
    cknex().select '*'
    .from 'addon_votes_by_creatorId'
    .where 'creatorId', '=', creatorId
    .andWhere 'addonId', '=', addonId
    .run {isSingle: true}


module.exports = new AddonVoteModel()
