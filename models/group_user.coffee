_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'
USER_ID_INDEX = 'userId'

defaultGroupUser = (groupUser) ->
  unless groupUser?
    return null

  if groupUser.groupId and groupUser.userId
    id = "#{groupUser.groupId}:#{groupUser.userId}"
  else
    id = uuid.v4()

  _.defaults groupUser, {
    id: id
    groupId: null
    userId: null
    roleId: null
    # globalPermissions:
    #   viewMessages: true
    #   createMessages: false
    #   deleteMessages: false
    #   manageChannels: false
    #   manageMembers: false
    #   manageRecords: false
    #   manageRoles: false
    #   manageSettings: false
    #   manageEvents: false
    # channelPermissions: {}
    time: new Date()
  }

GROUP_USERS_TABLE = 'group_users'

class GroupUserModel
  RETHINK_TABLES: [
    {
      name: GROUP_USERS_TABLE
      indexes: [
        {name: GROUP_ID_INDEX}
        {name: USER_ID_INDEX}
      ]
    }
  ]

  create: (groupUser) ->
    groupUser = defaultGroupUser groupUser

    r.table GROUP_USERS_TABLE
    .insert groupUser
    .run()
    .then ->
      groupUser

  getAllByGroupId: (groupId) ->
    console.log GROUP_USERS_TABLE, groupId, GROUP_ID_INDEX
    r.table GROUP_USERS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()

  getAllByUserId: (userId) ->
    r.table GROUP_USERS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .run()

  deleteByGroupIdAndUserId: (groupId, userId) ->
    r.table GROUP_USERS_TABLE
    .get "#{groupId}:#{userId}"
    .delete()
    .run()

  updateById: (id, diff) ->
    r.table GROUP_USERS_TABLE
    .get id
    .update diff
    .run()

module.exports = new GroupUserModel()
