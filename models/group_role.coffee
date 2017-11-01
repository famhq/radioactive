_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'

ONE_DAY_SECONDS = 3600 * 24

defaultGroupRole = (groupRole) ->
  unless groupRole?
    return null

  _.defaults groupRole, {
    roleId: uuid.v4()
  }

defaultGroupRoleOutput = (groupRole) ->
  unless groupRole?
    return null

  groupRole.globalPermissions = try
    JSON.parse groupRole.globalPermissions
  catch error
    {}

  groupRole

tables = [
  {
    name: 'group_roles_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      roleId: 'uuid'
      globalPermissions: 'text' # json
      channelPermissions: 'text' # json
    primaryKey:
      # a little uneven since some groups will have a lot of roles, but each
      # row is small
      partitionKey: ['groupId']
      clusteringColumns: ['roleId']
  }
]

class GroupRoleModel
  SCYLLA_TABLES: tables

  upsert: (groupRole) ->
    groupRole = defaultGroupRole groupRole

    groupRole.globalPermissions = JSON.stringify groupRole.globalPermissions

    cknex().update 'group_roles_by_groupId'
    .set _.omit groupRole, ['groupId', 'roleId']
    .where 'groupId', '=', groupRole.groupId
    .andWhere 'roleId', '=', groupRole.roleId
    .run()
    .then ->
      groupRole
    .tap ->
      prefix = CacheService.PREFIXES.GROUP_ROLE_GROUP_ID_USER_ID
      cacheKey = "#{prefix}:#{groupRole.groupId}:#{groupRole.userId}"
      CacheService.deleteByKey cacheKey

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'group_roles_by_groupId'
    .where 'groupId', '=', groupId
    .run()
    .map defaultGroupRoleOutput

  getByGroupIdAndRoleId: (groupId, roleId) ->
    cknex().select '*'
    .from 'group_roles_by_groupId'
    .where 'groupId', '=', groupId
    .andWhere 'roleId', '=', roleId
    .run {isSingle: true}
    .then defaultGroupRoleOutput

module.exports = new GroupRoleModel()
