_ = require 'lodash'
router = require 'exoid-router'
deck = require 'deck'
Promise = require 'bluebird'

Product = require '../models/product'
Item = require '../models/item'
UserItem = require '../models/user_item'
User = require '../models/user'
GroupUser = require '../models/group_user'
EmailService = require '../services/email'
CacheService = require '../services/cache'
config = require '../config'

TWO_MINUTE_SECONDS = 60 * 2

class ProductCtrl
  getAllByGroupId: ({groupId}, {user}) ->
    Product.getAllByGroupId groupId

  getAll: ({}, {user}) ->
    Product.getAll()

  getByKey: ({key}) ->
    Product.getByKey key


  getPackItems: (product) ->
    Item.getAllByGroupId product.groupId
    .then (items) ->
      groupedItems = _.groupBy items, 'rarity'
      odds = _.reduce product.data.odds, (obj, {rarity, odds}) ->
        if groupedItems[rarity]
          obj[rarity] = odds
        obj
      , {}
      packItems = _.map _.range(product.data.count or 1), (i) ->
        rarity = deck.pick odds
        population = groupedItems[rarity]
        _.sample population

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
        GroupUser.incrementXpByGroupIdAndUserId product.groupId, user.id, xpEarned

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

      cost = if key is 'no_ads_for_day' then 50 else 15000

      if user.fire < cost
        router.throw {status: 400, info: 'not enough fire'}

      User.subtractFireById user.id, cost
      .then (response) =>
        # double-check that they had the fire to buy
        # (for simulatenous purchases)
        unless response.replaced
          router.throw {status: 400, info: 'not enough fire'}

        EmailService.send {
          to: EmailService.EMAILS.EVERYONE
          subject: "Starfire Product Purchase: #{key}"
          text: """
          Username: #{user?.username}

          Country: #{user?.country}

          ID: #{key}

          Email: #{email}

          Cost: #{cost}
          """
        }

        if product.type is 'pack'
          @openPackUnlocked {key}, {user}


module.exports = new ProductCtrl()
