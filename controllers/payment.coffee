iap = require 'iap'
Promise = require 'bluebird'
fx = require 'money'
accounting = require 'accounting'
stripe = require 'stripe'
router = require 'exoid-router'

User = require '../models/user'
Transaction = require '../models/transaction'
Iap = require '../models/product'
config = require '../config'

ONE_DAY_MS = 3600 * 24 * 1000

stripe = stripe(config.STRIPE_SECRET_KEY)

fx.base = 'USD'
# http://api.fixer.io/latest?base=USD
fx.rates = require '../resources/data/exchange_rates.json'

completeVerifiedPurchase = (user, {iapKey, revenueCents}) ->
  Product.getByIapKey iapKey
  .then (product) ->
    revenueCents ?= product.price * 100

    isOneTimePurchase = product.isOneTimePurchase
    subsequentPurchaseGold = product.subsequentPurchaseGold

    inGameCurrency = product.type

    if product[inGameCurrency]
      {saleMultiplier, saleExpireTime} = Product.getSale product, user
      isOnSale = Boolean saleMultiplier and
        saleExpireTime.getTime() >= Date.now()
      currencyAmount = product[inGameCurrency]
      if isOnSale and saleMultiplier > 1
        currencyAmount *= saleMultiplier

      if isOneTimePurchase and user.flags?.oneTimePurchases?[iapKey]
        currencyAmount = subsequentPurchaseGold

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

        if isOneTimePurchase
          userDiff.flags?.oneTimePurchases = {"#{iapKey}": true}

        User.updateById user.id, userDiff

class PaymentCtrl
  purchase: (options) ->
    {iapKey, stripeToken, transactionId}
    transaction = {}

    Product.getByIapKey iapKey
    .then (product) ->
      priceCents = product.priceCents

      transaction =
        userId: user.id
        amountCents: priceCents
        iapKey: iapKey
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
            privateData:
              stripeCustomerId: customer.id
          }
      .then ->
        completeVerifiedPurchase user, {
          iapKey
          transactionId: transactionId
          revenueCents: priceCents
        }
      .then ->
        transaction.isCompleted = true
        Transaction.create transaction
        {iapKey}

      .catch (err) ->
        console.log err
        Transaction.create transaction
        throw new router.Error
          status: 400
          detail: 'Unable to verify payment'

  verify: (options) ->
    {platform, receipt, iapKey, packageName,
      isFromPending, currency, price, priceMicros} = options

    Product.getByIapKey iapKey
    .then (product) ->
      if priceMicros
        revenueLocal = parseInt(priceMicros) / 1000000
        console.log 'local (micro): ', revenueLocal, currency
      else
        priceStr = "#{price}"
        decimal = if priceStr[priceStr.length - 3] is ',' then ',' else '.'
        revenueLocal = accounting.unformat price, decimal

      console.log 'local: ', revenueLocal, currency
      if currency
        revenueUsd = try
          fx.convert(revenueLocal, {from: currency, to: 'USD'})
        catch err
          console.log 'conversion error'
          0
      else
        revenueUsd = revenueLocal

      revenueUsd or= product.priceCents / 100

      console.log 'usd:', revenueUsd
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
        iapKey: iapKey
        packageName: packageName
        keyObject: config.GOOGLE_PRIVATE_KEY_JSON

      transaction =
        userId: user.id
        amount: revenueUsd
        iapKey: iapKey
        isFromPending: isFromPending

      Promise.promisify(iap.verifyPayment) platform, payment
      .then ({iapKey, transactionId}) ->
        (if transactionId
          Transaction.getByTransactionId transactionId
        else
          Promise.resolve null
        )
        .then (existingTransaction) ->
          if existingTransaction
            console.log 'dupe txn'
            {iapKey, revenueUsd, transactionId, alreadyGiven: true}
          else
            completeVerifiedPurchase user, {
              iapKey
              transactionId
              revenueCents
            }
            .then ->
              transaction.isCompleted = true
              transaction.transactionId = transactionId
              Transaction.create transaction
              {iapKey, revenueUsd, transactionId}

      .catch (err) ->
        console.log err
        Transaction.create transaction
        throw new router.Error
          status: 400
          detail: 'Unable to verify payment'



module.exports = new PaymentCtrl()
