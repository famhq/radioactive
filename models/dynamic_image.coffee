_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

USER_ID_IMAGE_KEY_INDEX = 'userIdGameId'

defaultDynamicImage = (dynamicImage) ->
  unless dynamicImage?
    return null

  _.defaults dynamicImage, {
    id: uuid.v4()
    imageKey: null
    userId: null
    data: {}
  }

DYNAMIC_IMAGES_TABLE = 'dynamic_images'

class DynamicImagesModel
  RETHINK_TABLES: [
    {
      name: DYNAMIC_IMAGES_TABLE
      indexes: [
        {name: USER_ID_IMAGE_KEY_INDEX, fn: (row) ->
          [row('userId'), row('imageKey')]}
      ]
    }
  ]

  getByUserIdAndImageKey: (userId, imageKey) ->
    r.table DYNAMIC_IMAGES_TABLE
    .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultDynamicImage
    .then (dynamicImage) ->
      _.defaults {userId}, dynamicImage

  upsertByUserIdAndImageKey: (userId, imageKey, diff) ->
    r.table DYNAMIC_IMAGES_TABLE
    .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
    .nth 0
    .default null
    .do (dynamicImage) ->
      r.branch(
        dynamicImage.eq null

        r.table DYNAMIC_IMAGES_TABLE
        .insert defaultDynamicImage _.defaults _.clone(diff), {
          userId
          imageKey
        }

        r.table DYNAMIC_IMAGES_TABLE
        .getAll [userId, imageKey], {index: USER_ID_IMAGE_KEY_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then (a) ->
      null

module.exports = new DynamicImagesModel()
