_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

VIDEOS_TABLE = 'videos'
AUTHOR_ID_INDEX = 'authorId'
SOURCE_ID_INDEX = 'sourceId'
TIME_INDEX = 'time'

defaultVideo = (video) ->
  unless video?
    return null

  _.defaults video, {
    source: null
    sourceId: null
    title: null
    description: null
    duration: null
    authorName: null
    authorId: null
    time: new Date()
  }

class VideoModel
  RETHINK_TABLES: [
    {
      name: VIDEOS_TABLE
      options: {}
      indexes: [
        {name: SOURCE_ID_INDEX}
        {name: AUTHOR_ID_INDEX}
        {name: TIME_INDEX}
      ]
    }
  ]

  create: (video) ->
    video = defaultVideo video
    video.id = video.source + '-' + video.sourceId

    r.table VIDEOS_TABLE
    .get video.id
    .replace video
    .run()
    .then ->
      video

  getById: (id) ->
    r.table VIDEOS_TABLE
    .get id
    .run()
    .then defaultVideo

  getAll: ({sort} = {}) ->
    r.table VIDEOS_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit 20
    .run()
    .map defaultVideo

  updateById: (id, diff) ->
    r.table VIDEOS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table VIDEOS_TABLE
    .get id
    .delete()
    .run()

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
