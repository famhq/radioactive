Promise = require 'bluebird'
gm = require('gm').subClass({imageMagick: true})

AWSService = require './aws'
config = require '../config'

DEFAULT_IMAGE_QUALITY = 85

class ImageService
  DEFAULT_IMAGE_QUALITY: DEFAULT_IMAGE_QUALITY

  getSizeByBuffer: (buffer) ->
    new Promise (resolve, reject) ->
      gm(buffer)
      .size (err, size) ->
        if err
          reject err
        else
          resolve size

  toStream: ({buffer, path, width, height, quality, type, useMin}) ->
    quality ?= DEFAULT_IMAGE_QUALITY
    type ?= 'png'

    image = gm(buffer or path)

    if width or height
      mode = if width and height and not useMin then '^' else null
      image = image
        .resize width or height, height or width, mode

      if height
        image = image
        .gravity 'Center'
        .crop width, height, 0, 0

    if type is 'jpg'
      image = image
        .interlace 'Line' # progressive jpeg

    return image
      .quality DEFAULT_IMAGE_QUALITY
      .stream type

  # Note: images are never removed from s3
  uploadImage: ({key, stream, contentType}) ->
    contentType ?= 'image/png'

    bucket = new AWSService.S3()

    new Promise (resolve, reject) ->
      bucket.upload
        Key: key
        Bucket: config.AWS.CDN_BUCKET
        Body: stream
        ContentType: contentType
      .send (err) ->
        if err
          reject err
        else
          resolve key


module.exports = new ImageService()
