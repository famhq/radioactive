_ = require 'lodash'

uuid = require 'node-uuid'

cknex = require '../services/cknex'
User = require './user'
CacheService = require '../services/cache'

DEFAULT_UUID = '00000000-0000-0000-0000-000000000000'

defaultThreadVote = (threadVote) ->
  unless threadVote?
    return null

  _.defaults threadVote, {
    vote: 0 # -1 or 1
    time: new Date()
  }

# with this structure we'd need another table to get votes by parentId
tables = [
  {
    name: 'thread_votes_by_creatorId'
    keyspace: 'starfire'
    fields:
      creatorId: 'uuid'
      parentTopId: 'uuid' # eg threadId for threadComments
      parentType: 'text'
      parentId: 'uuid'
      vote: 'int'
      time: 'timestamp'
    primaryKey:
      # a little uneven since some users will vote a lot, but small data overall
      partitionKey: ['creatorId', 'parentTopId', 'parentType']
      clusteringColumns: ['parentId']
  }
]

class ThreadVoteModel
  SCYLLA_TABLES: tables

  upsertByCreatorIdAndParent: (creatorId, parent, threadVote) ->
    threadVote = defaultThreadVote threadVote

    cknex().update 'thread_votes_by_creatorId'
    .set threadVote
    .where 'creatorId', '=', creatorId
    .andWhere 'parentTopId', '=', parent.topId or DEFAULT_UUID
    .andWhere 'parentType', '=', parent.type
    .andWhere 'parentId', '=', parent.id
    .run()
    .then ->
      threadVote

  getByCreatorIdAndParent: (creatorId, parent) ->
    cknex().select '*'
    .from 'thread_votes_by_creatorId'
    .where 'creatorId', '=', creatorId
    .andWhere 'parentType', '=', parent.type
    .andWhere 'parentTopId', '=', parent.topId or DEFAULT_UUID
    .andWhere 'parentId', '=', parent.id
    .run {isSingle: true}

  getAllByCreatorIdAndParentTopId: (creatorId, parentTopId) ->
    cknex().select '*'
    .from 'thread_votes_by_creatorId'
    .where 'creatorId', '=', creatorId
    .where 'parentTopId', '=', parentTopId
    .where 'parentType', '=', 'threadComment'
    .run()

  getAllByCreatorIdAndParents: (creatorId, parents) ->
    cknex().select '*'
    .from 'thread_votes_by_creatorId'
    .where 'creatorId', '=', creatorId
    .andWhere 'parentTopId', '=', parents[0].topId or DEFAULT_UUID
    .andWhere 'parentType', '=', parents[0].type
    .andWhere 'parentId', 'in', _.map(parents, 'id')
    .run()


module.exports = new ThreadVoteModel()
