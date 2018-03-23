_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

# TODO: figure out how to bump. probably need to delete and re-create
# expired probably shouldn't be deleted, so they can be reposted...

# TODO: long ttl on lfg_by_userId so it can be reposted (bumped)

tables = [
  {
    name: 'lfg_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      hashtag: 'text'
      text: 'text'
      id: 'timeuuid'
    primaryKey:
      # 'all' is  blank '' hashtag
      partitionKey: ['groupId', 'hashtag']
      clusteringColumns: ['id']
    withClusteringOrderBy: ['id', 'desc']
  }
  {
    name: 'lfg_by_groupId_and_userId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      text: 'text'
      id: 'timeuuid'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId']
  }
]

defaultLfg = (lfg) ->
  unless lfg?
    return null

  _.defaults {
    hashtag: ''
    id: cknex.getTimeUuid()
  }, lfg

defaultLfgOutput = (lfg) ->
  unless lfg?
    return null

  lfg.userId = "#{lfg.userId}"
  lfg.groupId = "#{lfg.groupId}"
  lfg.time = lfg.id.getDate()

  lfg

ONE_DAY_SECONDS = 3600 * 24
ONE_MINUTE_SECONDS = 60

class LfgModel
  SCYLLA_TABLES: tables

  getHashtagsByText: (text) ->
    matches = text.match /\B#\w*[a-zA-Z]+\w*/g
    matches or []

  getByGroupIdAndUserId: (groupId, userId) ->
    cknex().select '*'
    .from 'lfg_by_groupId_and_userId'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .run {isSingle: true}
    .then defaultLfgOutput

  getAllByGroupIdAndHashtag: (groupId, hashtag, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .from 'lfg_by_groupId'
      .where 'groupId', '=', groupId
      .andWhere 'hashtag', '=', hashtag
      .limit 30 # FIXME
      .run()
      .map defaultLfgOutput

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.LFG_GET_ALL}:#{groupId}:#{hashtag}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: ONE_MINUTE_SECONDS
      }
    else
      get()

  upsert: (lfg) =>
    lfg = defaultLfg lfg

    hashtags = @getHashtagsByText lfg.text

    Promise.all _.flatten [
      cknex().update 'lfg_by_groupId_and_userId'
      .set _.omit lfg, ['userId', 'groupId', 'hashtag']
      .where 'userId', '=', lfg.userId
      .andWhere 'groupId', '=', lfg.groupId
      .run()

      _.map hashtags.concat(['']), (hashtag) ->
        cknex().update 'lfg_by_groupId'
        .set _.omit lfg, ['groupId', 'hashtag', 'id']
        .where 'groupId', '=', lfg.groupId
        .andWhere 'hashtag', '=', hashtag
        .andWhere 'id', '=', lfg.id
        .usingTTL ONE_DAY_SECONDS
        .run()
    ]
    .tap ->
      prefix = CacheService.PREFIXES.LFG_GET_ALL
      Promise.map hashtags.concat(['']), (hashtag) ->
        CacheService.deleteByKey "#{prefix}:#{lfg.groupId}:#{hashtag}"

  deleteByLfg: (lfg) =>
    hashtags = @getHashtagsByText lfg.text

    Promise.all _.flatten [
      cknex().delete()
      .from 'lfg_by_groupId_and_userId'
      .where 'userId', '=', lfg.userId
      .andWhere 'groupId', '=', lfg.groupId
      .run()

      _.map hashtags.concat(['']), (hashtag) ->
        cknex().delete()
        .from 'lfg_by_groupId'
        .where 'groupId', '=', lfg.groupId
        .andWhere 'hashtag', '=', hashtag
        .andWhere 'id', '=', lfg.id
        .run()
    ]
    .tap ->
      prefix = CacheService.PREFIXES.LFG_GET_ALL
      Promise.map hashtags.concat(['']), (hashtag) ->
        CacheService.deleteByKey "#{prefix}:#{lfg.groupId}:#{hashtag}"


module.exports = new LfgModel()
