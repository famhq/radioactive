_ = require 'lodash'
router = require 'exoid-router'
moment = require 'moment'
deck = require 'deck'
Promise = require 'bluebird'

GroupUser = require '../models/group_user'
UserItem = require '../models/user_item'
UserUpgrade = require '../models/user_upgrade'
Item = require '../models/item'
ItemService = require '../services/item'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.USER_ITEM.ITEM
]

TWO_MINUTES_SECONDS = 60 * 2

class UserItemCtrl
  getAll: ({}, {user}) ->
    UserItem.getAllByUserId user.id
    .map EmbedService.embed {embed: defaultEmbed}
    .then (userItems) ->
      _.filter userItems, 'item'

  getAllByUserId: ({userId}, {user}) ->
    UserItem.getAllByUserId userId
    .map EmbedService.embed {embed: defaultEmbed}
    # filter out items that no longer exist (ph/cr_es coin//scratch)
    .then (userItems) ->
      _.filter userItems, 'item'

  getByItemKey: ({itemKey}, {user}) ->
    UserItem.getByUserIdAndItemKey user.id, itemKey

  # upgradeByItemKey: ({itemKey}, {user}) ->
  #   prefix = CacheService.LOCK_PREFIXES.UPGRADE_STICKER
  #   key = "#{prefix}:#{user.id}:#{itemKey}"
  #   CacheService.lock key, ->
  #     UserItem.getByUserIdAndItemKey user.id, itemKey
  #     .then (userItem) ->
  #       currentLevel = userItem?.itemLevel or 1
  #       itemLevel = _.find(config.ITEM_LEVEL_REQUIREMENTS, {
  #         level: currentLevel + 1
  #         })
  #       console.log currentLevel,  userItem?.count, itemLevel?.countRequired
  #       unless userItem?.count >= itemLevel?.countRequired
  #         router.throw {status: 400, info: 'not enough stickers'}
  #
  #       # since level starts at 0 (not 1), we need to add 2 for level 2
  #       inc = if not userItem.itemLevel then 2 else 1
  #
  #       Item.incrementCirculatingByKeyAndLevel itemKey, currentLevel + 1, 1
  #
  #       UserItem.incrementLevelByItemKeyAndUserId itemKey, user.id, inc
  #   , {expireSeconds: TWO_MINUTES_SECONDS, unlockWhenCompleted: true}

  consumeByItemKey: ({itemKey, groupId}, {user}) ->
    prefix = CacheService.LOCK_PREFIXES.CONSUME_ITEM
    key = "#{prefix}:#{user.id}:#{itemKey}"
    CacheService.lock key, ->
      Promise.all [
        Item.getByKey itemKey
        UserItem.getByUserIdAndItemKey user.id, itemKey
        UserUpgrade.getByUserIdAndGroupIdAndItemKey user.id, groupId, itemKey
      ]
      .then ([item, userItem, userUpgrade]) ->
        unless userItem?.count > 0
          router.throw {status: 400, info: 'not enough items'}

        if userUpgrade?.expireTime
          baseExpireS = (userUpgrade.expireTime.getTime() - Date.now()) / 1000
          baseExpireS = Math.max baseExpireS, 0
        else
          baseExpireS = 0

        expireTime = moment(userUpgrade?.expireTime)
                                .add(item.data.duration, 'seconds').toDate()

        # since level starts at 0 (not 1), we need to add 2 for level 2
        Item.incrementCirculatingByKeyAndLevel itemKey, 1, -1

        Promise.all [
          UserItem.incrementByItemKeyAndUserId itemKey, user.id, -1
          UserUpgrade.upsert {
            groupId, itemKey, expireTime
            userId: user.id, upgradeType: item.data.upgradeType
          }, {ttl: baseExpireS + item.data.duration}
        ]
        .tap ->
          key = "#{CacheService.PREFIXES.CHAT_USER}:#{user.id}:#{groupId}"
          CacheService.deleteByKey key
    , {expireSeconds: TWO_MINUTES_SECONDS, unlockWhenCompleted: true}


  # _getOpenedtem: (item) ->
  #   Item.getAllByGroupId item.groupId
  #   .then (items) ->
  #     if item.data.itemKeys
  #       key = _.sample item.data.itemKeys
  #       console.log 'key', key, items
  #       return _.find items, {key}
  #     else
  #       groupedItems = _.groupBy items, ({type, rarity}) -> "#{type}|#{rarity}"
  #       odds = _.reduce item.data.odds, (obj, {type, rarity, odds}) ->
  #         if groupedItems["#{type}|#{rarity}"]
  #           obj["#{type}|#{rarity}"] = odds
  #         obj
  #       , {}
  #       typeAndRarity = deck.pick odds
  #       population = groupedItems[typeAndRarity]
  #       _.sample population

  openByItemKey: ({itemKey, groupId}, {user}) ->
    prefix = CacheService.LOCK_PREFIXES.OPEN_ITEM
    key = "#{prefix}:#{user.id}:#{itemKey}"
    CacheService.lock key, ->
      Promise.all [
        Item.getByKey itemKey
        UserItem.getByUserIdAndItemKey user.id, itemKey
      ]
      .then ([item, userItem]) ->
        unless item?.data?.keyRequired
          router.throw {status: 404, info: 'item not found'}
        unless userItem?.count > 0
          router.throw {status: 404, info: 'no chests'}

        Promise.all [
          Item.getByKey item.data.keyRequired
          UserItem.getByUserIdAndItemKey user.id, item.data.keyRequired
          ItemService.getItemsByGroupIdAndOdds item.groupId, {
            odds: item.data.odds
            count: item.data.count
            itemKeys: item.data.itemKeys
          }
        ]
        .then ([keyItem, keyUserItem, openedItems]) ->
          unless keyUserItem and keyUserItem.count > 0
            router.throw {status: 404, info: 'no keys'}

          Promise.all [
            UserItem.incrementByItemKeyAndUserId keyItem.key, user.id, -1
            UserItem.incrementByItemKeyAndUserId item.key, user.id, -1
            ItemService.incrementByGroupIdAndUserIdAndItems(
              item.groupId
              user.id
              openedItems
            )
          ]
          .then ->
            if _.isEmpty openedItems
              router.throw {status: 400, info: 'No items found'}

            openedItems

          # Item.batchIncrementCirculatingByItemKeys [openedItem.key]
          # xpEarned = config.RARITY_XP[openedItem.rarity]
          #
          # console.log 'inc', openedItem.key

          # Promise.all [
          #   UserItem.incrementByItemKeyAndUserId keyItem.key, user.id, -1
          #   UserItem.incrementByItemKeyAndUserId item.key, user.id, -1
          #   GroupUser.incrementXpByGroupIdAndUserId(
          #     groupId, user.id, xpEarned
          #   )
          #   UserItem.incrementByItemKeyAndUserId openedItem.key, user.id, 1
          # ]
          # .then ->
          #   item


    , {expireSeconds: TWO_MINUTES_SECONDS, unlockWhenCompleted: true}

module.exports = new UserItemCtrl()
