_ = require 'lodash'
request = require 'request-promise'
geoip = require 'geoip-lite'

SpecialOffer = require '../models/special_offer'
User = require '../models/user'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
config = require '../config'

ONE_DAY_MS = 3600 * 24 * 1000

class SpecialOfferCtrl
  getAll: ({country}, {user}) =>
    country = 'us'

    SpecialOffer.getAll {preferCache: true}
    .then @filterMapstreetOffers country, user.id
    .map EmbedService.embed {
      embed: [EmbedService.TYPES.SPECIAL_OFFER.TRANSACTION]
      userId: user.id
    }

  filterMapstreetOffers: (country, userId) ->
    (offers) ->
      mappstreetOffers = _.filter offers, ({defaultData}) ->
        defaultData.sourceType is 'mappstreet'
      mappstreetIds = _.map mappstreetOffers, ({defaultData, countryData}) ->
        data = _.defaults countryData[country], defaultData
        data.sourceId
      if _.isEmpty mappstreetIds
        return offers

      # TODO: cache
      request 'http://api.mappstreet.com',
        qs:
          target: 'offers'
          method: 'findAll'
          token: config.MAPPSTREET_PRIVATE_TOKEN
          campaign_ids: mappstreetIds.join ','
        json: true
      .then (response) ->
        offers = _.map offers, (offer) ->
          {defaultData, countryData} = offer
          data = _.defaults countryData[country], defaultData
          offerInfo = _.find response?.response?.data, {
            campaign_id: "#{data.sourceId}"
          }
          uc = "#{userId}%7C#{offer.id}" # userId|offerId
          if offerInfo
            _.defaults {
              trackUrl: "#{offerInfo.url}?uc=#{uc}"
            }, offer
          else
            offer

        _.filter offers, ({defaultData, trackUrl}) ->
          return defaultData.sourceType isnt 'mappstreet' or trackUrl

  logClickById: ({id, deviceId}, {user}) ->
    SpecialOffer.getTransactionByUserIdAndOfferId user.id, id
    .then (transaction) ->
      unless transaction
        SpecialOffer.upsertTransaction {
          offerId: id
          userId: user.id
          deviceId: deviceId
          status: 'clicked'
        }

  giveDailyReward: (options, {user, headers, connection}) ->
    {offer, usageStats, deviceId} = options

    prefix = CacheService.LOCK_PREFIXES.SPECIAL_OFFER_DAILY
    key = "#{prefix}:#{offer.id}|#{user.id}"
    CacheService.lock key, ->
      ip = headers['x-forwarded-for'] or
            connection.remoteAddress
      country = geoip.lookup(ip)?.country
      Promise.all [
        SpecialOffer.getById offer.id
        SpecialOffer.getTransactionByUserIdAndOfferId user.id, offer.id
        SpecialOffer.getTransactionByDeviceIdAndOfferId deviceId, offer.id
      ]
      .then ([offer, transaction, transactionByDeviceId]) ->
        if transactionByDeviceId and
            "#{transactionByDeviceId.userId}" isnt "#{user.id}"
          router.throw status: 400, info: 'specialOffers: multiple deviceId'
        if transaction.status isnt 'installed'
          router.throw status: 400, info: 'specialOffers: invalid status'

        data = _.defaults offer.countryData[country], offer.defaultData
        dailyPayout = data.dailyPayout
        unless dailyPayout
          router.throw status: 400, info: 'specialOffers: no payout'

        minutesPlayed = Math.floor(
          usageStats.TotalTimeInForeground / (60 * 1000)
        )

        if minutesPlayed < data.minutesPerDay
          router.throw status: 400, info: 'specialOffers: not enough minutes'

        dt = Date.now() - transaction.startTime.getTime()
        day = Math.floor dt / ONE_DAY_MS

        if transaction.days[day]
          router.throw status: 400, info: 'specialOffers: day exists'

        Promise.all [
          User.addFireById user.id, dailyPayout
          SpecialOffer.upsertTransaction {
            offerId: offer.id
            userId: user.id
            deviceId: deviceId
            fireEarned: transaction.fireEarned + dailyPayout
            status: 'completed' # TODO: handle > 1 day
          }, {
            map: {
              days:
                "#{day}": JSON.stringify {
                  isCompleted: true, minutes: minutesPlayed
                }
            }
          }
        ]
    , {expireSeconds: 10, unlockWhenCompleted: true}

  giveInstallReward: (options, {user, headers, connection}) ->
    {offer, usageStats, deviceId} = options
    prefix = CacheService.LOCK_PREFIXES.SPECIAL_OFFER_INSTALL
    key = "#{prefix}:#{offer.id}|#{user.id}"
    CacheService.lock key, ->
      ip = headers['x-forwarded-for'] or
            connection.remoteAddress
      country = geoip.lookup(ip)?.country
      Promise.all [
        SpecialOffer.getById offer.id
        SpecialOffer.getTransactionByUserIdAndOfferId user.id, offer.id
        SpecialOffer.getTransactionByDeviceIdAndOfferId deviceId, offer.id
      ]
      .then ([offer, transaction, transactionByDeviceId]) ->
        if transactionByDeviceId and
            "#{transactionByDeviceId.userId}" isnt "#{user.id}"
          router.throw status: 400, info: 'specialOffers: multiple deviceId'
        if transaction.status isnt 'clicked'
          router.throw status: 400, info: 'specialOffers: invalid inst status'

        data = _.defaults offer.countryData[country], offer.defaultData
        installPayout = data.installPayout
        unless installPayout
          router.throw status: 400, info: 'specialOffers: no payout'

        Promise.all [
          User.addFireById user.id, installPayout
          SpecialOffer.upsertTransaction {
            offerId: offer.id
            userId: user.id
            deviceId: deviceId
            status: 'installed'
            startTime: new Date()
            days: []
            fireEarned: installPayout
          }
        ]
    , {expireSeconds: 10, unlockWhenCompleted: true}

module.exports = new SpecialOfferCtrl()
