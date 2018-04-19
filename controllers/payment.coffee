iap = require 'iap'
Promise = require 'bluebird'
fx = require 'money'
accounting = require 'accounting'
stripe = require 'stripe'
router = require 'exoid-router'

User = require '../models/user'
UserPrivateData = require '../models/user_private_data'
GroupRecord = require '../models/group_record'
Transaction = require '../models/transaction'
Iap = require '../models/iap'
config = require '../config'

ONE_DAY_MS = 3600 * 24 * 1000

stripe = stripe(config.STRIPE_SECRET_KEY)

fx.base = 'USD'
# http://api.fixer.io/latest?base=USD
fx.rates = require '../resources/data/exchange_rates.json'

completeVerifiedPurchase = (user, options) ->
  {platform, groupId, iapKey, revenueCents, transactionId} = options
  Iap.getByPlatformAndKey platform, iapKey
  .then (iap) ->
    console.log 'go iap', iap
    fireAmount = iap.data.fireAmount

    if isNaN fireAmount
      console.log 'payment: NaN fireAmount'
      return {}
    else
      GroupRecord.incrementByGroupIdAndRecordTypeKey(
        groupId, 'fireEarned', fireAmount
      )

      User.addFireById user.id, fireAmount

class PaymentCtrl
  purchase: (options, {user}) ->
    {groupId, iapKey, stripeToken, transactionId, platform} = options
    transaction = {}

    console.log 'ppp', platform, iapKey

    Promise.all [
      Iap.getByPlatformAndKey platform, iapKey
      UserPrivateData.getByUserId user.id
    ]
    .then ([iap, userPrivateData]) ->
      priceCents = iap.priceCents

      transaction =
        userId: user.id
        amountCents: priceCents
        iapKey: iapKey
        id: transactionId

      (if stripeToken
        stripe.customers.create({
          source: stripeToken,
          description: user.id
        })
      else if userPrivateData.data.stripeCustomerId
        Promise.resolve {id: userPrivateData.data.stripeCustomerId}
      else
        router.throw
          status: 400
          info: 'No token'
      ).then (customer) ->
        stripe.charges.create({
          amount: priceCents
          currency: 'usd'
          customer: customer.id
          metadata: {
            orderId: '' # TODO
          }
        })
        .then ->
          Promise.all [
            User.updateById user.id, {
              flags:
                hasStripeId: true
            }
            UserPrivateData.upsert {
              userId: user.id
              data:
                stripeCustomerId: customer.id
            }
          ]
      .then ->
        completeVerifiedPurchase user, {
          groupId
          iapKey
          platform
          id: transactionId
          revenueCents: priceCents
        }
      .then ->
        transaction.isCompleted = true
        Transaction.upsert transaction
        {iapKey}

      .catch (err) ->
        console.log err
        Transaction.upsert transaction
        router.throw
          status: 400
          info: 'Unable to verify payment'

  verify: (options, {user}) ->
    {platform, groupId, receipt, iapKey, packageName,
      isFromPending, currency, price, priceMicros} = options

    Iap.getByPlatformAndKey platform, iapKey
    .then (iap) ->
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

      revenueUsd or= iap.priceCents / 100

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
          Transaction.getById transactionId
        else
          Promise.resolve null
        )
        .then (existingTransaction) ->
          if existingTransaction
            console.log 'dupe txn'
            {iapKey, revenueUsd, transactionId, alreadyGiven: true}
          else
            completeVerifiedPurchase user, {
              groupId
              iapKey
              transactionId
              revenueCents
            }
            .then ->
              transaction.isCompleted = true
              transaction.id = transactionId
              Transaction.upsert transaction
              {iapKey, revenueUsd, transactionId}

      .catch (err) ->
        console.log err
        Transaction.upsert transaction
        router.throw
          status: 400
          info: 'Unable to verify payment'



module.exports = new PaymentCtrl()
