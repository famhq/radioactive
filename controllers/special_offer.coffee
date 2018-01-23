_ = require 'lodash'
request = require 'request-promise'
geoip = require 'geoip-lite'
router = require 'exoid-router'

SpecialOffer = require '../models/special_offer'
User = require '../models/user'
GroupRecord = require '../models/group_record'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
config = require '../config'

ONE_DAY_MS = 3600 * 24 * 1000
ONE_HOUR_SECONDS = 60 * 3600

class SpecialOfferCtrl
  getAll: ({limit}, {user, headers, connection}) =>
    limit ?= 20
    key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
    CacheService.preferCache key, =>
      ip = headers['x-forwarded-for'] or
            connection.remoteAddress
      country = geoip.lookup(ip)?.country
      SpecialOffer.getAll {limit}, {preferCache: true}
      .then @filterMapstreetOffers country, user.id
      .map EmbedService.embed {
        embed: [EmbedService.TYPES.SPECIAL_OFFER.TRANSACTION]
        userId: user.id
      }
      .then (offers) ->
        offers = _.filter offers, (offer) ->
          not offer?.transaction? or
            not (offer.transaction.status in ['completed', 'failed'])

        offers = _.map offers, (offer) ->
          _.defaults {meCountryData: offer.countryData[country]}, offer
        _.orderBy offers, (offer) ->
          offer.defaultData.priority or 0
        , 'desc'
    , {expireSeconds: ONE_HOUR_SECONDS}
    .then (offers) ->
      _.take offers, limit

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
            _.defaultsDeep {
              defaultData:
                trackUrl: "#{offerInfo.url}?uc=#{uc}"
            }, offer
          else
            offer

        _.filter offers, ({defaultData}) ->
          defaultData.sourceType isnt 'mappstreet' or defaultData.trackUrl

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
        .tap ->
          key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
          CacheService.deleteByKey key

  giveDailyReward: (options, {user, headers, connection}) ->
    {offer, usageStats, deviceId, groupId} = options

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
          SpecialOffer.upsertTransaction {
            offerId: offer.id
            userId: user.id
            deviceId: deviceId
            status: 'failed'
          }
          .tap ->
            key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
            CacheService.deleteByKey key
          router.throw status: 400, info: 'specialOffers: multiple deviceId'
        if not transaction.status in ['installed', 'playing']
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

        # TODO
        if day >= data.days
          status = 'completed'
        else
          status = 'playing'

        GroupRecord.incrementByGroupIdAndRecordTypeKey(
          groupId, 'fireEarned', dailyPayout
        )

        Promise.all [
          User.addFireById user.id, dailyPayout
          SpecialOffer.upsertTransaction {
            offerId: offer.id
            userId: user.id
            deviceId: deviceId
            fireEarned: transaction.fireEarned + dailyPayout
            status: status
          }, {
            map: {
              days:
                "#{day}": JSON.stringify {
                  isCompleted: true, minutes: minutesPlayed
                }
            }
          }
        ]
        .tap ->
          key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
          CacheService.deleteByKey key
    , {expireSeconds: 10, unlockWhenCompleted: true}

  giveInstallReward: (options, {user, headers, connection}) ->
    {offer, usageStats, deviceId, groupId} = options
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
          SpecialOffer.upsertTransaction {
            offerId: offer.id
            userId: user.id
            deviceId: deviceId
            status: 'failed'
          }
          .tap ->
            key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
            CacheService.deleteByKey key
          router.throw status: 400, info: 'specialOffers: multiple deviceId'
        if transaction.status isnt 'clicked'
          router.throw status: 400, info: 'specialOffers: invalid inst status'

        data = _.defaults offer.countryData[country], offer.defaultData
        installPayout = data.installPayout
        unless installPayout
          router.throw status: 400, info: 'specialOffers: no payout'

        GroupRecord.incrementByGroupIdAndRecordTypeKey(
          groupId, 'fireEarned', installPayout
        )

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
        .tap ->
          key = "#{CacheService.PREFIXES.USER_SPECIAL_OFFERS}:#{user.id}"
          CacheService.deleteByKey key
    , {expireSeconds: 10, unlockWhenCompleted: true}

module.exports = new SpecialOfferCtrl()
