_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

defaultSpecialOffer = (specialOffer) ->
  unless specialOffer?
    return null

  specialOfferClone = _.clone specialOffer

  specialOfferClone.countryData = JSON.stringify specialOffer.countryData
  specialOfferClone.defaultData = JSON.stringify specialOffer.defaultData

  _.defaults specialOfferClone, {
    id: uuid.v4()
    timeBucket: 'all' # not enough that we'd need to group for now
    addTime: new Date()
  }

defaultSpecialOfferOutput = (specialOffer) ->
  specialOffer.countryData = try
    JSON.parse specialOffer.countryData
  catch err
    null
  specialOffer.defaultData = try
    JSON.parse specialOffer.defaultData
  catch err
    null

  specialOffer

tables = [
  {
    name: 'special_offers'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      name: 'text'
      iOSPackage: 'text'
      androidPackage: 'text'
      backgroundImage: 'text'
      backgroundColor: 'text'
      textColor: 'text'
      countryData: 'text' # [{installPayout, dailyPayout, days, minutesPerDay}]
      defaultData: 'text' # {installPayout, dailyPayout, days, minutesPerDay}
      timeBucket: 'text'
      addTime: 'timestamp'
    primaryKey:
      partitionKey: ['timeBucket']
      clusteringColumns: ['id']
  }
  {
    name: 'special_offer_transactions'
    keyspace: 'starfire'
    fields:
      offerId: 'uuid'
      userId: 'uuid'
      status: 'text' # active
      # track x number of days, y fire per days
      startTime: 'timestamp'
      days: 'text' # [{isClaimed, minutesPlayed}]
      fireEarned: 'int'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['userId', 'timeBucket']
      clusteringColumns: ['offerId']
  }
]

FIVE_MINUTES_S = 60 * 5

class SpecialOfferModel
  SCYLLA_TABLES: tables

  batchUpsert: (specialOffers) =>
    Promise.map specialOffers, (specialOffer) =>
      @upsert specialOffer, {skipRun: true}

  getAll: ({preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .from 'special_offers'
      .run()
      .map defaultSpecialOfferOutput

    if preferCache
      cacheKey = CacheService.KEYS.SPECIAL_OFFER_ALL
      CacheService.preferCache cacheKey, get, {expireSeconds: FIVE_MINUTES_S}
    else
      get()

  createTransaction: (transaction) ->
    null

  getAllTransactionsByUserIdAndOfferIds: (userId, offerIds) ->
    cknex().select '*'
    .from 'special_offer_transactions'
    .where 'userId', '=', userId
    .andWhere 'timeBucket', '=', 'all'
    .andWhere 'offerId', 'in', offerIds
    .run()

  upsert: (specialOffer) ->
    specialOffer = defaultSpecialOffer specialOffer

    cknex().update 'special_offers'
    .set _.omit specialOffer, ['timeBucket', 'id']
    .where 'id', '=', specialOffer.id
    .andWhere 'timeBucket', '=', specialOffer.timeBucket
    .run()

module.exports = new SpecialOfferModel()
