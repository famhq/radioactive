_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

DynamicImage = require '../models/dynamic_image'

class DynamicImageCtrl
  getMeByImageKey: ({imageKey}, {user}) ->
    DynamicImage.getByUserIdAndImageKey user.id, imageKey

  upsertMeByImageKey: ({imageKey, diff}, {user}) ->
    data = _.pick diff, ['color', 'favoriteCard']
    DynamicImage.upsertByUserIdAndImageKey user.id, imageKey, {data: data}

module.exports = new DynamicImageCtrl()
