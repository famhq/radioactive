_ = require 'lodash'
Promise = require 'bluebird'

products = require '../resources/data/products'

class ProductModel
  RETHINK_TABLES: []

  getAll: ->
    Promise.resolve products

  getByProductId: (productId) ->
    Promise.resolve _.find products, {productId}

  getSale: (product, user) ->
    userSale = _.first _.filter user.sales, ({productIds, expireTime}) ->
      productIds.indexOf(product.productId) isnt -1 and
        expireTime.getTime() > Date.now()
    productSaleMultiplier = product.saleMultiplier or 1

    if userSale and userSale?.multiplier > productSaleMultiplier
      return {
        saleMultiplier: userSale?.multiplier
        saleExpireTime: userSale?.expireTime
      }
    else
      return {
        saleMultiplier: product.saleMultiplier
        saleExpireTime: product.saleExpireTime
      }


module.exports = new ProductModel()
