_ = require 'lodash'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

defaultGroupPage = (groupPage) ->
  unless groupPage?
    return null

  if groupPage.data
    groupPage.data = JSON.stringify groupPage.data

  groupPage

defaultGroupPageOutput = (groupPage) ->
  unless groupPage?
    return null

  if groupPage.data
    groupPage.data = try
      JSON.parse groupPage.data
    catch err
      {}

  groupPage

tables = [
  {
    name: 'group_pages_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      key: 'text'
      data: 'text' # JSON title, body, lastUpdateTime, etc...
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['key']
  }
]

class GroupPageModel
  SCYLLA_TABLES: tables

  upsert: (groupPage) ->
    groupPage = defaultGroupPage groupPage

    cknex().update 'group_pages_by_groupId'
    .set _.omit groupPage, ['groupId', 'key']
    .where 'groupId', '=', groupPage.groupId
    .andWhere 'key', '=', groupPage.key
    .run()
    .then ->
      groupPage

  deleteByGroupIdAndKey: (groupId, key) ->
    cknex().delete()
    .from 'group_pages_by_groupId'
    .where 'groupId', '=', groupId
    .andWhere 'key', '=', key
    .run()

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'group_pages_by_groupId'
    .where 'groupId', '=', groupId
    .run()
    .map defaultGroupPageOutput

  getByGroupIdAndKey: (groupId, key) ->
    cknex().select '*'
    .from 'group_pages_by_groupId'
    .where 'groupId', '=', groupId
    .andWhere 'key', '=', key
    .run {isSingle: true}
    .then defaultGroupPageOutput

module.exports = new GroupPageModel()
