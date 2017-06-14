_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'
CacheService = require '../services/cache'

defaultThreadVote = (threadVote) ->
  unless threadVote?
    return null

  id = "#{threadVote.parentId}:#{threadVote.creatorId}"

  _.defaults threadVote, {
    id: id
    creatorId: null
    parentId: null
    parentType: 'thread'
    vote: 0 # -1 or 1
    time: new Date()
  }

THREAD_VOTES_TABLE = 'thread_votes'
CREATOR_ID_PARENT_ID_PARENT_TYPE_INDEX = 'creatorIdParentIdParentType'
MAX_MESSAGES = 30

class ThreadVoteModel
  RETHINK_TABLES: [
    {
      name: THREAD_VOTES_TABLE
      indexes: [
        {name: CREATOR_ID_PARENT_ID_PARENT_TYPE_INDEX, fn: (row) ->
          [row('creatorId'), row('parentId'), row('parentType')]}
      ]
    }
  ]

  create: (threadVote) ->
    threadVote = defaultThreadVote threadVote

    r.table THREAD_VOTES_TABLE
    .insert threadVote
    .run()
    .then ->
      threadVote

  updateById: (id, diff) ->
    r.table THREAD_VOTES_TABLE
    .get id
    .update diff
    .run()

  getByCreatorIdAndParent: (creatorId, parentId, parentType) ->
    r.table THREAD_VOTES_TABLE
    .getAll [creatorId, parentId, parentType], {
      index: CREATOR_ID_PARENT_ID_PARENT_TYPE_INDEX
    }
    .nth 0
    .default null
    .run()
    .then defaultThreadVote

  getById: (id) ->
    r.table THREAD_VOTES_TABLE
    .get id
    .run()
    .then defaultThreadVote

module.exports = new ThreadVoteModel()
