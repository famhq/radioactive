Promise = require 'bluebird'

User = require '../models/user'
PushNotificationService = require './push_notification'
config = require '../config'

class ProductService
  # from kue
  productUnlocked: ({userId, groupId, productKey, productName}) ->
    User.getById userId, {preferCache: true}
    .then (user) ->
      PushNotificationService.send user, {
        titleObj:
          key: 'packUnlocked.title'
        type: PushNotificationService.TYPES.PRODUCT
        url: "https://#{config.SUPERNOVA_HOST}"
        textObj:
          key: 'packUnlocked.text'
          replacements:
            packName: productName
        data:
          path:
            key: 'groupShop'
            params: {id: groupId}
      }


module.exports = new ProductService()
