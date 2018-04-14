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
    .then EmbedService.embed {embed: defaultEmbed}

  consumeByItemKey: ({itemKey, groupId, data}, {user}) ->
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

        data = _.pick data, ['color']
        if data?.color
          isHex = data.color.match /^#(?:[0-9a-fA-F]{3}){1,2}$/
          unless isHex
            router.throw {status: 400, info: 'invalid hex'}

          isBaseItem = item.data.upgradeType.indexOf('Base') isnt -1
          if isBaseItem and
              config.BASE_NAME_COLORS.indexOf(data.color) is -1
            router.throw {status: 400, info: 'invalid color'}

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
            groupId, itemKey, expireTime, data
            userId: user.id, upgradeType: item.data.upgradeType
          }, {ttl: baseExpireS + item.data.duration}
        ]
        .tap ->
          key = "#{CacheService.PREFIXES.CHAT_USER}:#{user.id}:#{groupId}"
          CacheService.deleteByKey key
    , {expireSeconds: TWO_MINUTES_SECONDS, unlockWhenCompleted: true}

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
