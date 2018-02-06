log = require 'loga'
_ = require 'lodash'
Promise = require 'bluebird'

PushNotificationService = require './push_notification'
User = require '../models/user'
UserItem = require '../models/user_item'
Trade = require '../models/trade'
ItemService = require '../services/item'
EmbedService = require '../services/embed'
# CheatService = require '../services/cheat'
config = require '../config'

MIN_ITEM_IDS_TO_TRADE = 20
ONE_DAY_MS = 3600 * 24 * 1000

MIN_FLAGGED_TRADES_TO_BAN = 5
MIN_FLAGGED_FIRE_TO_BAN = 100000
MIN_FAIRNESS_FOR_NEW_USER_TRADE = 0.34
# TODO: optimize
# used for fairness
RARITY_RATES = {
  common: 0.8
}

# item value is 1 / RARITY_RATES[item.type]
# blue is ~1.3, crystal is ~200
FIRE_VALUE_PER_CARD_VALUE = 100
MAX_RARITY_FOR_RARE = 0.01
MIN_FIRE_FOR_FLAG = 14000
# crystal cost = 80000

class TradeService
  # we could technically prevent flagged trades, but we want there to be
  # punishment for attempting to cheat
  # isFlagged: ({sendItems, sendFire, receiveItems, receiveFire}) ->
  #   # legendary items, or sending a lot of fire for
  #   # (1 blue or green item or 100 fire)
  #   hasRareItem = _.some sendItems, ({item}) ->
  #     rarity = RARITY_RATES[item.subTypes[0]] or RARITY_RATES['unknown']
  #     rarity <= MAX_RARITY_FOR_RARE
  #
  #   receiveLargeFire = (sendFire - receiveFire) >= MIN_FIRE_FOR_FLAG
  #   isReturnFireSmall = (receiveFire - sendFire) <= 300
  #
  #   isLt10Cards = receiveItems.length < 10
  #   isReturnItemsCommon = isLt10Cards and _.every receiveItems, ({item}) ->
  #     item.subTypes[0] in ['blue', 'green', 'red', 'silver']
  #
  #   flaggedCard = (hasRareItem and isReturnFireSmall and isReturnItemsCommon)
  #   flaggedFire = receiveLargeFire and isReturnItemsCommon
  #
  #   return flaggedCard or flaggedFire

  # getFairness: ({sendItems, sendFire, receiveItems, receiveFire}) ->
  #   # ultra rare value = 100, common is ~1.4
  #   # 20 packs for 1 ultra rare (3000 fire)
  #   # 1 item value = 30 fire
  #   sendValue = _.sumBy sendItems, ({item, count}) ->
  #     rarity = RARITY_RATES[item.subTypes?[0]] or RARITY_RATES['unknown']
  #     count / rarity
  #   sendValue += sendFire / FIRE_VALUE_PER_CARD_VALUE
  #   receiveValue = _.sumBy receiveItems, ({item, count}) ->
  #     rarity = RARITY_RATES[item.subTypes?[0]] or RARITY_RATES['unknown']
  #     count / rarity
  #   receiveValue += receiveFire / FIRE_VALUE_PER_CARD_VALUE
  #
  #   netValue = receiveValue - sendValue
  #
  #   # 1 is the highest score, closest to 1 is more fair
  #   fairness = Math.min(sendValue, receiveValue) /
  #               Math.max(sendValue, receiveValue)
  #   tradeFavors = if sendValue > receiveValue then 'to' else 'from'
  #   isFair = fairness > MIN_FAIRNESS_FOR_NEW_USER_TRADE
  #
  #   {fairness, tradeFavors, isFair, netValue}

  acceptTrade: (tradeId, user) =>
    isBot = user.id is '0'

    diff = {status: 'approved'}
    Trade.getById tradeId
    .then EmbedService.embed {embed: [EmbedService.TYPES.TRADE.ITEMS]}
    .then (trade) =>
      unless trade
        throw {
          status: 400
          detail: 'Trade no longer exists'
        }

      unless trade.status is 'pending'
        throw {
          status: 400
          detail: 'Trade status must be pending'
        }

      unless "#{trade.toId}" is "#{user.id}"
        throw {
          status: 400
          detail: 'Trade not for you'
        }

      if "#{trade.fromId}" is "#{user.id}"
        throw {
          status: 400
          detail: 'Trade from you'
        }



      Promise.all [
        User.getById trade.fromId
        UserItem.getAllByUserId trade.fromId
        UserItem.getAllByUserId user.id
      ]
      .then ([fromUser, fromUserItems, meUserItems]) =>

        # cheat stuff...
        # isFromNewUser = fromUser.joinTime.getTime() > Date.now() - ONE_DAY_MS
        # isMeNewUser = user.joinTime.getTime() > Date.now() - ONE_DAY_MS
        # the problem with this is it's very difficult to detect what is and
        # isn't a fair trade... eg some users will give up a silver item for
        # 300 fire, while others want 3,000.
        # {fairness, tradeFavors, isFair} = @getFairness trade
        # console.log {fairness, tradeFavors, isFair}
        # isFairForFrom = isFair or tradeFavors is 'from'
        # isFairForTo = isFair or tradeFavors is 'to'
        # ipsMatch = fromUser.ip and fromUser.ip is user.ip
        # two new users can unfairly trade between eachother (husband/wife?)
        # if not isBot and isFromNewUser and not isFairForFrom and
        #     not isMeNewUser and ipsMatch
        #   throw {
        #     status: 400
        #     detail: 'This doesn\'t look like a fair trade for them'
        #   }
        # if trade.sendFire and fromUser.itemKeys < MIN_ITEM_IDS_TO_TRADE and
        #     ipsMatch
        #   throw {
        #     status: 400
        #     detail: 'Sender can\'t trade for fire yet'
        #   }
        # if not isBot and isMeNewUser and not isFairForTo and
        #     not isFromNewUser and ipsMatch
        #   throw {
        #     status: 400
        #     detail: 'This doesn\'t look like a fair trade for you'
        #   }


        # if not isBot and trade.receiveFire and
        #     user.itemKeys < MIN_ITEM_IDS_TO_TRADE and
        #       ipsMatch
        #   throw {
        #     status: 400
        #     detail: 'Receiver (me) can\'t trade for fire yet'
        #   }




        # fire stuff...
        # meFire = user.fire
        # fromUserFire = fromUser.fire
        # if fromUserFire < trade.sendFire
        #   throw {
        #     status: 400
        #     detail: 'Sender doesn\'t have enough fire'
        #   }
        #
        # if meFire < trade.receiveFire
        #   throw {
        #     status: 400
        #     detail: 'Receiver (me) doesn\'t have enough fire'
        #   }
        # fromUserNewFire = fromUserFire - trade.sendFire + trade.receiveFire
        # meNewFire = meFire - trade.receiveFire + trade.sendFire

        # fromDiff = {
        #   fire: fromUserNewFire
        # }
        # toDiff = {
        #   fire: meNewFire
        # }

        {receiveItemKeys, sendItemKeys} = trade

        fromUserItemIncrements = {}

        console.log fromUserItems

        fromUserItemIncrements = _.reduce sendItemKeys, (inc, itemKey) ->
          {itemKey, count} = itemKey
          hasItem = ItemService.findItemKey fromUserItems, itemKey
          unless hasItem and hasItem.count >= count
            throw {
              status: 400
              detail: 'Sender item not found: ' + itemKey
            }
          inc[itemKey] ?= 0
          inc[itemKey] -= count
          inc
        , fromUserItemIncrements

        fromUserItemIncrements = _.reduce receiveItemKeys, (inc, itemKey) ->
          {itemKey, count} = itemKey
          inc[itemKey] ?= 0
          inc[itemKey] += count
          inc
        , fromUserItemIncrements

        meUserItemIncrements = {}

        meUserItemIncrements = _.reduce receiveItemKeys, (inc, itemKey) ->
          {itemKey, count} = itemKey
          hasItem = ItemService.findItemKey meUserItems, itemKey
          unless hasItem and hasItem.count >= count
            throw {
              status: 400
              detail: 'Receiver (me) item not found: ' + itemKey
            }
          inc[itemKey] ?= 0
          inc[itemKey] -= count
          inc
        , meUserItemIncrements

        meUserItemIncrements = _.reduce sendItemKeys, (inc, itemKey) ->
          {itemKey, count} = itemKey
          inc[itemKey] ?= 0
          inc[itemKey] += count
          inc
        , meUserItemIncrements

        # Trade.getLastDayByUserIds user.id, fromUser.id
        # .then (lastDayTrades) =>
        #   @checkIfReceivingPreviouslySentCard(
        #     user, fromUser, lastDayTrades, trade
        #   )
        #   .then (checkIfReceivingPreviouslySentCard) =>
        #     if checkIfReceivingPreviouslySentCard
        #       @getNetFireBetweenPlayers user, fromUser, lastDayTrades, trade
        #       .then (netFire) ->
        #         if Math.abs(netFire) > MIN_FLAGGED_FIRE_TO_BAN
        #           CheatService.banIfCheating user, force = true
        #           CheatService.banIfCheating fromUser, force = true

        # if isFairForFrom and not isFair and @isFlagged {
        #   # swapped on purpose
        #   sendItems: trade.receiveItems
        #   sendFire: trade.receiveFire
        #   receiveItems: trade.sendItems
        #   receiveFire: trade.sendFire
        # }
        #   diff.isFlagged = true
        #   flaggedTrades = if fromUser.dailyData.flaggedTrades \
        #                   then fromUser.dailyData.flaggedTrades + 1
        #                   else 1
        #   flaggedFire = (fromUser.dailyData.flaggedFire or 0) +
        #                   trade.receiveFire
        #   User.updateDailyData trade.fromId, {flaggedTrades, flaggedFire}
        #   # if flaggedTrades >= MIN_FLAGGED_TRADES_TO_BAN
        #   #   CheatService.banIfCheating fromUser
        # else if isFairForTo and not isFair and @isFlagged trade
        #   diff.isFlagged = true
        #   flaggedTrades = if user.dailyData.flaggedTrades \
        #                   then user.dailyData.flaggedTrades + 1
        #                   else 1
        #   flaggedFire = (user.dailyData.flaggedFire or 0) + trade.sendFire
        #   User.updateDailyData user.id, {flaggedTrades, flaggedFire}
        #   if flaggedTrades >= MIN_FLAGGED_TRADES_TO_BAN or
        #       flaggedFire >= MIN_FLAGGED_FIRE_TO_BAN
        #     CheatService.banIfCheating user


        Promise.all [
          # User.updateById trade.fromId, fromDiff
          UserItem.batchIncrementByCountsAndUserId(
            fromUserItemIncrements, trade.fromId
          )

          # User.updateById user.id, toDiff
          UserItem.batchIncrementByCountsAndUserId meUserItemIncrements, user.id
        ]
        .tap ->
          PushNotificationService.send fromUser, {
            titleObj:
              key: 'acceptedTrade.title'
            textObj:
              key: 'acceptedTrade.text'
              replacements:
                name: User.getDisplayName(user)
            type: PushNotificationService.TYPES.TRADE
            data:
              path:
                key: 'trades'
          }
          .catch (err) ->
            console.log err
          null
        .then ->
          Trade.upsert _.defaults diff, _.pick(trade, ['toId', 'fromId', 'id'])
          .then ->
            Trade.getById tradeId
          .then EmbedService.embed {
            embed: [
              EmbedService.TYPES.TRADE.ITEMS
              EmbedService.TYPES.TRADE.USERS
            ]
          }
          .then Trade.sanitize(null)

  # checkIfReceivingPreviouslySentCard: (user, fromUser, lastDayTrades, trade) ->
  #   user1Items = []
  #   user2Items = []
  #
  #   Promise.map lastDayTrades, (trade) ->
  #     user1Items = _.filter user1Items.concat if trade.fromId is user.id \
  #                                             then trade.sendItemKeys
  #                                             else trade.receiveItemKeys
  #     user2Items = _.filter user2Items.concat if trade.fromId is fromUser.id \
  #                                             then trade.sendItemKeys
  #                                             else trade.receiveItemKeys
  #   .then ->
  #     isDupe1 = _.some trade.sendItems, ({id}) ->
  #       _.find user1Items, {id}
  #     isDupe2 = _.some trade.receiveItems, ({id}) ->
  #       _.find user2Items, {id}
  #     isDupe1 or isDupe2
  #
  #
  # getNetFireBetweenPlayers: (user, fromUser, lastDayTrades, trade) ->
  #   netFire = 0
  #
  #   Promise.map lastDayTrades.concat([trade]), (trade) ->
  #     user1Fire = if trade.fromId is user.id \
  #                 then trade.sendFire
  #                 else trade.receiveFire
  #     user2Fire = if trade.fromId is fromUser.id \
  #                 then trade.sendFire
  #                 else trade.receiveFire
  #
  #     netFire += user1Fire
  #     netFire -= user2Fire
  #   .then ->
  #     netFire

module.exports = new TradeService()
