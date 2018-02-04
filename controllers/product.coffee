_ = require 'lodash'
router = require 'exoid-router'
deck = require 'deck'
Promise = require 'bluebird'

Product = require '../models/product'
Item = require '../models/item'
UserItem = require '../models/user_item'
User = require '../models/user'
GroupUser = require '../models/group_user'
GroupRecord = require '../models/group_record'
KueCreateService = require '../services/kue_create'
EmailService = require '../services/email'
CacheService = require '../services/cache'
config = require '../config'

TWO_MINUTE_SECONDS = 60 * 2

class ProductCtrl
  getAllByGroupId: ({groupId}, {user}) ->
    Promise.all [
      Product.getAllByGroupId groupId
      Product.getLocksByUserIdAndGroupId user.id, groupId
    ]
    .then ([products, locks]) ->
      _.filter _.map products, (product) ->
        lock = _.find locks, {productKey: product.key}
        if lock and lock['ttl(time)']
          _.defaults {
            isLocked: true, lockExpireSeconds: lock['ttl(time)']
          }, product
        else if not lock
          product

  getByKey: ({key}) ->
    Product.getByKey key

  getPackItems: (product) ->
    Item.getAllByGroupId product.groupId
    .then (items) ->
      groupedItems = _.groupBy items, ({type, rarity}) -> "#{type}|#{rarity}"
      if product.data.odds
        odds = _.reduce product.data.odds, (obj, {type, rarity, odds}) ->
          if groupedItems["#{type}|#{rarity}"]
            obj["#{type}|#{rarity}"] = odds
          obj
        , {}
        packItems = _.map _.range(product.data.count or 1), (i) ->
          typeAndRarity = deck.pick odds
          population = groupedItems[typeAndRarity]
          _.sample population
      else
        packItems = _.map product.data.itemKeys, (itemKey) ->
          _.find items, {key: itemKey}

      packItems = _.shuffle packItems

      _.filter packItems

  # TODO move to separate file
  openPackUnlocked: ({key}, {user}) =>
    Product.getByKey key
    .then (product) =>
      @getPackItems product
      .then (packItems) ->
        if _.isEmpty packItems
          router.throw {status: 400, info: 'No items found'}

        itemKeys = _.map packItems, 'key'
        Item.batchIncrementCirculatingByItemKeys itemKeys

        xpEarned = _.sumBy packItems, ({rarity}) ->
          config.RARITY_XP[rarity]
        GroupUser.incrementXpByGroupIdAndUserId(
          product.groupId, user.id, xpEarned
        )

        UserItem.batchIncrementByItemKeysAndUserId itemKeys, user.id
        .then ->
          packItems

  openPack: ({key}, {user}) =>
    # if previous pack open is still going, don't allow another
    cacheKey = "#{CacheService.LOCK_PREFIXES.OPEN_PACK}:#{user.id}"
    CacheService.lock cacheKey, =>
      @openPackUnlocked {key}, {user}
    , {unlockWhenCompleted: true, expireSeconds: TWO_MINUTE_SECONDS}
    .then (result) ->
      if result
        result
      else
        router.throw status: 400, info: {isLocked: true}

  buy: ({key, email}, {user}) =>
    Product.getByKey key
    .then (product) =>
      unless product
        router.throw {status: 400, info: 'item not found'}

      if user.fire < product.cost
        router.throw {status: 400, info: 'not enough fire'}

      (if product.data.lockTime
        Product.getLockByProductAndUserId product, user.id
        .then (lock) ->
          if lock
            router.throw {status: 400, info: 'locked'}
          else if product.data.lockTime isnt 'infinity'
            KueCreateService.createJob {
              job:
                userId: user.id
                groupId: product.groupId
                productKey: product.key
                productName: product.name
              type: KueCreateService.JOB_TYPES.PRODUCT_UNLOCKED
              delayMs: product.data.lockTime * 1000
            }
          Product.setLockByProductAndUserId product, user.id
      else
        Promise.resolve null)
      .then ->
        User.subtractFireById user.id, product.cost
      .then (response) =>
        # double-check that they had the fire to buy
        # (for simulatenous purchases)
        if product.cost isnt 0 and not response.replaced
          router.throw {status: 400, info: 'not enough fire'}

        if product.cost
          GroupRecord.incrementByGroupIdAndRecordTypeKey(
            product.groupId, 'fireSpent', product.cost
          )

        EmailService.send {
          to: EmailService.EMAILS.EVERYONE
          subject: "Starfire Product Purchase: #{key}"
          text: """
          Username: #{user?.username}

          Country: #{user?.country}

          ID: #{key}

          Email: #{email}

          Cost: #{product.cost}
          """
        }
        .catch (err) ->
          console.log 'email err', err

        if product.type is 'pack'
          @openPackUnlocked {key}, {user}


module.exports = new ProductCtrl()
