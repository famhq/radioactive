_ = require 'lodash'
uuid = require 'node-uuid'
moment = require 'moment'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'

defaultGroupRole = (groupRole) ->
  unless groupRole?
    return null

  _.defaults groupRole, {
    id: uuid.v4()
    creatorId: null
    globalPermissions:
      viewMessages: true
      createMessages: false
      deleteMessages: false
      manageChannels: false
      manageMembers: false
      manageRecords: false
      manageRoles: false
      manageSettings: false
      manageEvents: false
    channelPermissions: {}
    time: new Date()
  }

GROUP_ROLES_TABLE = 'group_roles'

class GroupRoleModel
  RETHINK_TABLES: [
    {
      name: GROUP_ROLES_TABLE
      indexes: [
        {name: GROUP_ID_INDEX}
      ]
    }
  ]

  create: (groupRole) ->
    groupRole = defaultGroupRole groupRole

    r.table GROUP_ROLES_TABLE
    .insert groupRole
    .run()
    .then ->
      groupRole

  getAllByGroupId: (groupId) ->
    r.table GROUP_ROLES_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()

  getAllByIds: (ids) ->
    r.table GROUP_ROLES_TABLE
    .getAll ids, {index: GROUP_ID_INDEX}
    .run()

  updateById: (id, diff) ->
    r.table GROUP_ROLES_TABLE
    .get id
    .update diff
    .run()

module.exports = new GroupRoleModel()
