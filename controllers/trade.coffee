_ = require 'lodash'
Joi = require 'joi'
router = require 'exoid-router'
Promise = require 'bluebird'

Trade = require '../models/trade'
User = require '../models/user'
PushNotificationService = require '../services/push_notification'
TradeService = require '../services/trade'
EmbedService = require '../services/embed'
config = require '../config'
schemas = require '../schemas'

GET_ALL_USER_SUGGESTIONS_LIMIT = 10
TRADE_LENGTH_S = 3600 * 24 # 1 day
MAX_TRADES = 50 # TODO: paging

defaultEmbed = [EmbedService.TYPES.TRADE.ITEMS, EmbedService.TYPES.TRADE.USERS]

class TradeCtrl
  create: ({sendItemKeys, receiveItemKeys, toIds}, {user}) ->
    sendItemKeys or= []
    receiveItemKeys or= []

    embedUser = [EmbedService.TYPES.USER.DATA]
    Promise.map toIds, (userId) ->
      User.getById(userId).then EmbedService.embed embedUser
    .then (toUsers) ->
      # toUsers = _.filter toUsers, (user) ->
      #   user and user.data.blockedUserIds.indexOf(user.id) is -1
      toIds = _.map toUsers, 'id'
      Promise.map toUsers, (toUser) ->
        Trade.upsert {
          sendItemKeys
          receiveItemKeys
          fromId: user.id
          toId: toUser.id
        }, {ttl: TRADE_LENGTH_S}
        .tap (trade) ->
          sendObj =
            titleObj:
              key: 'newTrade.title'
            textObj:
              key: 'newTrade.text'
              replacements: {
                name: User.getDisplayName(user)
              }
            type: PushNotificationService.TYPES.TRADE
            data:
              path:
                key: 'trade'
                params:
                  id: trade.id

          PushNotificationService.send toUser, sendObj
          null

    .then Trade.sanitize(null)

  getAll: ({}, {user}) ->
    Promise.all [
      Trade.getAllByToId user.id, {limit: MAX_TRADES}
      Trade.getAllByFromId user.id, {limit: MAX_TRADES}
    ]
    .then ([toMe, fromMe]) ->
      if toMe or fromMe
        (toMe or []).concat fromMe
      else
        []
    .map EmbedService.embed {embed: defaultEmbed}
    .map Trade.sanitize(user.id)

  getById: ({id}) ->
    Trade.getById id
    .tap (trade) ->
      unless trade
        router.throw status: 404, detail: 'trade not found'
    .then EmbedService.embed {embed: defaultEmbed}
    .then Trade.sanitize(null)

  updateById: ({id, status}, {user}) ->
    diff = {status}

    updateSchema =
      status: Joi.string()

    diff = _.pick diff, _.keys(updateSchema)
    updateValid = Joi.validate diff, updateSchema

    if updateValid.error
      router.throw status: 400, detail: updateValid.error.message

    TradeService.acceptTrade id, user
    # .catch (err) ->
    #   router.throw err

  declineById: ({id}, {user}) ->
    Trade.getById id
    .then EmbedService.embed {embed: [EmbedService.TYPES.TRADE.USERS]}
    .then (trade) ->
      unless trade
        router.throw status: 404, detail: 'trade not found'

      if "#{trade.toId}" isnt "#{user.id}"
        router.throw status: 401, detail: 'not authorized'

      PushNotificationService.send(trade.from, {
        titleObj:
          key: 'rejectedTrade.title'
        textObj:
          key: 'rejectedTrade.text'
          replacements: {
            name: User.getDisplayName(user)
          }
        type: PushNotificationService.TYPES.TRADE
        data:
          path:
            key: 'trade'
            params:
              id: trade.id
      }).catch (err) ->
        console.log err

      diff = {status: 'declined'}
      Trade.upsert _.defaults diff, _.pick(trade, ['toId', 'fromId', 'id'])

  deleteById: ({id}, {user}) ->
    Trade.getById id
    .then (trade) ->
      unless trade
        router.throw status: 404, detail: 'trade not found'

      if "#{trade.fromId}" isnt "#{user.id}"
        router.throw status: 401, detail: 'not authorized'

      Trade.deleteByTrade trade
      .then ->
        null


module.exports = new TradeCtrl()
