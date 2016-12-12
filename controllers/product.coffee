_ = require 'lodash'

Product = require '../models/product'

class ProductCtrl
  getAll: ({}, {user}) ->
    Product.getAll()
    .map (product) ->
      {saleMultiplier, saleExpireTime} = Product.getSale(
        product, user
      )
      product.embeddedSaleMultiplier = saleMultiplier
      product.embeddedSaleExpireTime = saleExpireTime
      product
    .filter (product) ->
      not user.flags.oneTimePurchases or
        not user.flags.oneTimePurchases[product.productId]

  getById: ({productId}) ->
    Product.getByProductId productId

module.exports = new ProductCtrl()
