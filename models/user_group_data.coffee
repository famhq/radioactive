_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
schemas = require '../schemas'

USER_GROUP_DATA_TABLE = 'user_group_data'
USER_ID_GROUP_ID_INDEX = 'userIdGroupId'

# FIXME FIXME: delete, replace with group_user

defaultUserGroupData = (userGroupData) ->
  # unless userGroupData?
  #   return {}

  _.defaults userGroupData, {
    id: uuid.v4()
    userId: null
    groupId: null
    globalBlockedNotifications: {}
    roleIds: []
    gameData: {}
  }

class UserGroupDataModel
  RETHINK_TABLES: [
    {
      name: USER_GROUP_DATA_TABLE
      indexes: [
        {name: USER_ID_GROUP_ID_INDEX, fn: (row) ->
          [row('userId'), row('groupId')]}
      ]
    }
  ]

  getById: (id) ->
    r.table USER_GROUP_DATA_TABLE
    .get id
    .run()
    .then defaultUserGroupData

  getByUserIdAndGroupId: (userId, groupId) ->
    r.table USER_GROUP_DATA_TABLE
    .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultUserGroupData
    .then (userGroupData) ->
      _.defaults {userId}, userGroupData

  upsertByUserIdAndGroupId: (userId, groupId, diff) ->
    r.table USER_GROUP_DATA_TABLE
    .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
    .nth 0
    .default null
    .do (userGroupData) ->
      r.branch(
        userGroupData.eq null

        r.table USER_GROUP_DATA_TABLE
        .insert defaultUserGroupData _.defaults _.clone(diff), {userId, groupId}

        r.table USER_GROUP_DATA_TABLE
        .getAll [userId, groupId], {index: USER_ID_GROUP_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

  # sanitize: _.curry (requesterId, userGroupData) ->
  #   _.pick userGroupData, _.keys schemas.userGroupData

module.exports = new UserGroupDataModel()
