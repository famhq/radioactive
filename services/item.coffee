log = require 'loga'
_ = require 'lodash'
deck = require 'deck'
Promise = require 'bluebird'
uuid = require 'node-uuid'

Item = require '../models/item'
UserItem = require '../models/user_item'
GroupUser = require '../models/group_user'
config = require '../config'

class ItemService
  getAssetPath: (item) ->
    if item?.data?.year > 1
      null

  bundleItemKeys: (itemKeysArray) ->
    [].concat itemKeysArray

  removeItem: (items, findItem, count = 1) =>
    items = _.cloneDeep items
    index = @findItem items, findItem, {findIndex: true}
    if index isnt -1 and items[index]?.count > count
      items[index].count -= count
    else if index isnt -1
      items.splice index, 1
    items

  removeItemKey: (itemKeys, findItemKey, count = 1) =>
    itemKeys = _.cloneDeep itemKeys
    index = @findItemKey itemKeys, findItemKey, {findIndex: true}
    if index isnt -1 and itemKeys[index]?.count > count
      itemKeys[index].count -= count
    else if index isnt -1
      itemKeys.splice index, 1
    itemKeys

  addItemKey: (itemKeys, addedItemKey, count = 1) =>
    itemKeys = _.cloneDeep itemKeys
    index = @findItemKey itemKeys, addedItemKey, {findIndex: true}
    if index isnt -1
      itemKeys[index].count += count
    else
      itemKeys?.push _.defaults {count: count}, addedItemKey
    itemKeys

  addItem: (items, addedItem, count = 1) =>
    items = _.cloneDeep items
    index = @findItem items, addedItem, {findIndex: true}
    if index isnt -1
      items[index].count += count
    else
      items.push _.defaults {count: count}, addedItem
    items

  addItemKeys: (itemKeys, ids) =>
    _.each ids, (id) =>
      itemKeys = @addItemKey itemKeys, id
    itemKeys

  findItemKey: (itemKeys, findItemKey, {findIndex} = {}) ->
    findIndex ?= false

    findFn = if findIndex then _.findIndex else _.find
    findFn itemKeys, (itemKey) ->
      findItemKey is itemKey.itemKey

  findItem: (items, findItem, {findIndex} = {}) ->
    findIndex ?= false

    findFn = if findIndex then _.findIndex else _.find
    findFn items, (item) ->
      findItem.item.key is item.item.key

  getItemsByGroupIdAndOdds: (groupId, {odds, count, itemKeys}) ->
    Item.getAllByGroupId groupId
    .then (items) ->
      groupedItems = _.groupBy items, ({type, tier, rarity}) ->
        "#{type}|#{tier}|#{rarity}"
      if odds
        odds = _.reduce odds, (obj, {type, tier, rarity, odds}) ->
          if groupedItems["#{type}|#{tier}|#{rarity}"]
            obj["#{type}|#{tier}|#{rarity}"] = odds
          obj
        , {}
        items = _.map _.range(count or 1), (i) ->
          typeTierAndRarity = deck.pick odds
          population = groupedItems[typeTierAndRarity]
          _.sample population
      else
        items = _.map itemKeys, (itemKey) ->
          _.find items, {key: itemKey}

      items = _.shuffle items

      _.filter items

  incrementByGroupIdAndUserIdAndItems: (groupId, userId, items) ->
    itemKeys = _.map items, 'key'
    Item.batchIncrementCirculatingByItemKeys itemKeys

    # TODO: re-enable when cheating is fixed
    # xpEarned = _.sumBy items, ({rarity}) ->
    #   config.RARITY_XP[rarity]
    # GroupUser.incrementXpByGroupIdAndUserId(
    #   groupId, userId, xpEarned
    # )

    UserItem.batchIncrementByItemKeysAndUserId itemKeys, userId

module.exports = new ItemService()
