_ = require 'lodash'
router = require 'exoid-router'

Product = require '../models/product'
User = require '../models/user'
EmailService = require '../services/email'

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

  getById: ({id}) ->
    Product.getByProductId id

  buy: ({id, email}, {user}) ->
    unless id in ['noAdsForDay', 'googlePlay10', 'visa10']
      router.throw {status: 400, info: 'item not found'}
    cost = if id is 'noAdsForDay' then 150 else 15000

    if user.fire < cost
      router.throw {status: 400, info: 'not enough fire'}

    User.subtractFireById user.id, cost
    .then (response) ->
      # double-check that they had the fire to buy
      # (for simulatenous purchases)
      unless response.replaced
        router.throw {status: 400, info: 'not enough fire'}

      EmailService.send {
        to: EmailService.EMAILS.EVERYONE
        subject: 'Starfire Product Purchase'
        text: """
        Username: #{user?.username}

        Country: #{user?.country}

        ID: #{id}

        Email: #{email}

        Cost: #{cost}
        """
      }


module.exports = new ProductCtrl()
