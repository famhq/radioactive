_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

ONE_HOUR_SECONDS = 3600

defaultVideo = (video) ->
  unless video?
    return null

  _.defaults video, {
    id: uuid.v4()
    source: null
    sourceId: null
    title: null
    description: null
    duration: null
    authorName: null
    authorId: null
    time: new Date()
  }

defaultVideoOutput = (video) ->
  unless video?
    return null

  video.thumbnailImage = try
    JSON.parse video.thumbnailImage
  catch error
    null

  video

tables = [
  {
    name: 'videos_by_groupId'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      groupId: 'uuid'
      source: 'text'
      sourceId: 'text'
      title: 'text'
      description: 'text'
      duration: 'text'
      authorName: 'text'
      authorId: 'text'
      thumbnailImage: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['time']
    withClusteringOrderBy: ['time', 'desc']
  }
  {
    name: 'videos_by_id'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      groupId: 'uuid'
      source: 'text'
      sourceId: 'text'
      title: 'text'
      description: 'text'
      duration: 'text'
      authorName: 'text'
      authorId: 'text'
      thumbnailImage: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['id']
  }
]

class VideoModel
  SCYLLA_TABLES: tables

  upsert: (video) ->
    video = defaultVideo video

    Promise.all [
      cknex().update 'videos_by_groupId'
      .set _.omit video, [
        'groupId', 'time'
      ]
      .where 'groupId', '=', video.groupId
      .andWhere 'time', '=', video.time
      .run()

      cknex().update 'videos_by_id'
      .set _.omit video, [
        'id'
      ]
      .where 'id', '=', video.id
      .run()
    ]
    .then ->
      cacheKey = "#{CacheService.PREFIXES.VIDEOS_GROUP_ID}:#{video.groupId}"
      CacheService.deleteByKey cacheKey
      video

  getById: (id) ->
    cknex().select '*'
    .from 'videos_by_id'
    .where 'id', '=', id
    .run {isSingle: true}
    .then defaultVideoOutput

  getAllByGroupId: (groupId, {limit, sort, preferCache} = {}) ->
    limit ?= 15
    get = ->
      cknex().select '*'
      .from 'videos_by_groupId'
      .where 'groupId', '=', groupId
      .limit limit
      .run()
      .map defaultVideoOutput

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.VIDEOS_GROUP_ID}:#{groupId}:#{limit}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: ONE_HOUR_SECONDS
      }
    else
      get()

  getAllByGroupIdAndMinTime: (groupId, minTime) ->
    cknex().select '*'
    .from 'videos_by_groupId'
    .where 'groupId', '=', groupId
    .andWhere 'time', '>=', minTime
    .run()
    .map defaultVideoOutput

  sanitize: _.curry (requesterId, video) ->
    _.pick video, [
      'id'
      'source'
      'sourceId'
      'title'
      'description'
      'duration'
      'authorName'
      'authorId'
      'thumbnailImage'
      'time'
    ]

module.exports = new VideoModel()
