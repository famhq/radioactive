_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'

FOLLOWING_ID = 'followingId'
USER_ID_INDEX = 'userId'

defaultUserFollower = (userFollower) ->
  unless userFollower?
    return null

  if userFollower.followingId and userFollower.userId
    id = "#{userFollower.userId}:#{userFollower.followingId}"
  else
    id = uuid.v4()

  _.defaults userFollower, {
    id: id
    userId: null
    followingId: null
    time: new Date()
  }

USER_FOLLOWERS_TABLE = 'user_followers'

class UserFollowerModel
  RETHINK_TABLES: [
    {
      name: USER_FOLLOWERS_TABLE
      indexes: [
        {name: FOLLOWING_ID}
        {name: USER_ID_INDEX}
      ]
    }
  ]

  create: (userFollower) ->
    userFollower = defaultUserFollower userFollower

    r.table USER_FOLLOWERS_TABLE
    .insert userFollower
    .run()
    .then ->
      userFollower

  getAllByFollowingId: (followingId) ->
    r.table USER_FOLLOWERS_TABLE
    .getAll followingId, {index: FOLLOWING_ID}
    .run()

  getCountByFollowingId: (followingId) ->
    r.table USER_FOLLOWERS_TABLE
    .getAll followingId, {index: FOLLOWING_ID}
    .count()
    .run()

  getAllByUserId: (userId) ->
    r.table USER_FOLLOWERS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .run()

  deleteByFollowingIdAndUserId: (followingId, userId) ->
    r.table USER_FOLLOWERS_TABLE
    .get "#{userId}:#{followingId}"
    .delete()
    .run()

  updateById: (id, diff) ->
    r.table USER_FOLLOWERS_TABLE
    .get id
    .update diff
    .run()

module.exports = new UserFollowerModel()
