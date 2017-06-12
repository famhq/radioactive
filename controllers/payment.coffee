iap = require 'iap'
Promise = require 'bluebird'
fx = require 'money'
accounting = require 'accounting'
stripe = require 'stripe'
router = require 'exoid-router'

User = require '../models/user'
Transaction = require '../models/transaction'
Product = require '../models/product'
config = require '../config'

ONE_DAY_MS = 3600 * 24 * 1000

stripe = stripe(config.STRIPE_SECRET_KEY)

fx.base = 'USD'
# http://api.fixer.io/latest?base=USD
fx.rates = require '../resources/data/exchange_rates.json'

completeVerifiedPurchase = (user, {productId, revenueCents}) ->
  Product.getByProductId productId
  .then (product) ->
    revenueCents ?= product.price * 100

    inGameCurrency = product.type

    if product[inGameCurrency]
      {saleMultiplier, saleExpireTime} = Product.getSale product, user
      isOnSale = Boolean saleMultiplier and
        saleExpireTime.getTime() >= Date.now()
      currencyAmount = product[inGameCurrency]
      if isOnSale and saleMultiplier > 1
        currencyAmount *= saleMultiplier

      if isNaN currencyAmount
        console.log 'payment: NaN currencyAmount'
        return {}
      else
        userDiff = {
          "#{inGameCurrency}": user[inGameCurrency] + currencyAmount
          premiumExpireTime: new Date Date.now() + ONE_DAY_MS
          flags:
            isPayingUser: true
        }

        User.updateById user.id, userDiff

class PaymentCtrl
  purchase: (options, {user}) ->
    {product, stripeToken, transactionId} = options
    priceCents = product.price * 100

    transaction =
      userId: user.id
      amount: product.amount
      toUsername: product.username
      transactionId: transactionId

    (if stripeToken
      stripe.customers.create({
        source: stripeToken,
        description: user.id
      })
    else if user.privateData.stripeCustomerId
      Promise.resolve {id: user.privateData.stripeCustomerId}
    )
    .then (customer) ->
      stripe.charges.create({
        amount: priceCents
        currency: 'usd'
        customer: customer.id
        metadata: {
          orderId: '' # TODO
        }
      })
      .then ->
        User.updateSelf user.id, {
          flags:
            hasStripeId: true
          # FIXME FIXME
          privateData:
            stripeCustomerId: customer.id
        }
      .then ->
        completeVerifiedPurchase user, {
          productId
          transactionId: transactionId
          revenueCents: priceCents
        }
      .then ->
        transaction.isCompleted = true
        Transaction.create transaction
        {productId}

      .catch (err) ->
        console.log err
        Transaction.create transaction
        router.throw
          status: 400
          info: 'Unable to verify payment'

  # TODO: check that transactionId is only processed once (iap.verifyPayment
  # returns this). Will need to start storing transactions in rethink
  verify: (options, {user}) ->
    {platform, receipt, productId, packageName, isFromPending,
      currency, priceMicros, price} = options

    Product.getByProductId productId
    .then (product) ->
      if priceMicros
        revenueLocal = parseInt(priceMicros) / 1000000
      else
        priceStr = "#{price}"
        decimal = if priceStr[priceStr.length - 3] is ',' then ',' else '.'
        revenueLocal = accounting.unformat price, decimal

      if currency
        revenueUsd = try
          fx.convert(revenueLocal, {from: currency, to: 'USD'})
        catch err
          console.log 'conversion error'
          0
      else
        revenueUsd = revenueLocal

      revenueUsd or= product.price

      revenueCents = Math.floor(revenueUsd * 100)

      # isNaN when coming from getPending (on android, at least)
      if isNaN revenueCents
        console.log "invalid revenue #{price}"
        revenueCents = 0

      platform = if platform is 'android' \
                 then 'google'
                 else if platform is 'ios'
                 then 'apple'
                 else platform

      platform = platform
      payment =
        receipt: receipt
        productId: productId
        packageName: packageName
        keyObject: config.GOOGLE_PRIVATE_KEY_JSON

      transaction =
        userId: user.id
        amount: revenueCents / 100
        productId: productId
        isFromPending: isFromPending

      Promise.promisify(iap.verifyPayment) platform, payment
      .then ({productId, transactionId}) ->
        (if transactionId
          Transaction.getByTransactionId transactionId
        else
          Promise.resolve null
        )
        .then (existingTransaction) ->
          if existingTransaction
            {productId, revenueUsd, transactionId, alreadyGiven: true}
          else
            completeVerifiedPurchase user, {
              productId
              transactionId
              revenueCents
            }
            .then ->
              transaction.isCompleted = true
              transaction.transactionId = transactionId
              Transaction.create transaction
              {productId, revenueUsd, transactionId}

      .catch (err) ->
        Transaction.create transaction
        router.throw
          status: 400
          info: 'Unable to verify payment'



module.exports = new PaymentCtrl()
