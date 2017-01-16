_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
schemas = require '../schemas'

GROUP_USER_DATA_TABLE = 'group_user_data'
USER_ID_GROUP_ID_INDEX = 'userIdGroupId'

defaultGroupUserData = (groupUserData) ->
  # unless groupUserData?
  #   return {}

  _.defaults groupUserData, {
    id: uuid.v4()
    userId: null
    groupId: null
    globalBlockedNotifications: {}
  }

class GroupUserDataModel
  RETHINK_TABLES: [
    {
      name: GROUP_USER_DATA_TABLE
      indexes: [
        {name: USER_ID_GROUP_ID_INDEX, fn: (row) ->
          [row('userId'), row('groupId')]}
      ]
    }
  ]

  getById: (id) ->
    r.table GROUP_USER_DATA_TABLE
    .get id
    .run()
    .then defaultGroupUserData

  getByUserIdAndGroupId: (userId, groupId) ->
    r.table GROUP_USER_DATA_TABLE
    .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultGroupUserData
    .then (groupUserData) ->
      _.defaults {userId}, groupUserData

  upsertByUserIdAndGroupId: (userId, groupId, diff) ->
    r.table GROUP_USER_DATA_TABLE
    .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
    .nth 0
    .default null
    .do (groupUserData) ->
      r.branch(
        groupUserData.eq null

        r.table GROUP_USER_DATA_TABLE
        .insert defaultGroupUserData _.defaults _.clone(diff), {userId, groupId}

        r.table GROUP_USER_DATA_TABLE
        .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  # sanitize: _.curry (requesterId, groupUserData) ->
  #   _.pick groupUserData, _.keys schemas.groupUserData

module.exports = new GroupUserDataModel()
