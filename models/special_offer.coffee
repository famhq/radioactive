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

defaultSpecialOfferTransaction = (specialOfferTransaction) ->
  unless specialOfferTransaction?
    return null

  _.defaults specialOfferTransaction, {
    timeBucket: 'all' # not enough that we'd need to group for now
  }

defaultSpecialOfferTransactionOutput = (specialOfferTransaction) ->
  unless specialOfferTransaction?
    return null

  days = specialOfferTransaction.days
  specialOfferTransaction.days = _.mapValues days, (day) ->
    try
      JSON.parse day
    catch err
      null

  specialOfferTransaction


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
      deviceId: 'text'
      status: 'text' # active
      # track x number of days, y fire per days
      startTime: 'timestamp'
      # [{isClaimed, minutesPlayed}]
      days: {type: 'map', subType: 'int', subType2: 'text'}
      fireEarned: 'int'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['userId', 'timeBucket']
      clusteringColumns: ['offerId']
  }
  {
    name: 'special_offer_transactions_by_deviceId'
    keyspace: 'starfire'
    fields:
      offerId: 'uuid'
      userId: 'uuid'
      deviceId: 'text'
      status: 'text' # active
      # track x number of days, y fire per days
      startTime: 'timestamp'
      # [{isClaimed, minutesPlayed}]
      days: {type: 'map', subType: 'int', subType2: 'text'}
      fireEarned: 'int'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['deviceId', 'timeBucket']
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
      # without this might be causing db crashes?
      .where 'timeBucket', '=', 'all'
      .run()
      .map defaultSpecialOfferOutput

    if preferCache
      cacheKey = CacheService.KEYS.SPECIAL_OFFER_ALL
      CacheService.preferCache cacheKey, get, {expireSeconds: FIVE_MINUTES_S}
    else
      get()

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .from 'special_offers'
      .where 'timeBucket', '=', 'all'
      .andWhere 'id', '=', id
      .run {isSingle: true}
      .then defaultSpecialOfferOutput

    if preferCache
      cacheKey = CacheService.KEYS.SPECIAL_OFFER_ID
      CacheService.preferCache cacheKey, get, {expireSeconds: FIVE_MINUTES_S}
    else
      get()

  getTransactionByUserIdAndOfferId: (userId, offerId) ->
    cknex().select '*'
    .from 'special_offer_transactions'
    .where 'userId', '=', userId
    .andWhere 'timeBucket', '=', 'all'
    .andWhere 'offerId', '=', offerId
    .run {isSingle: true}
    .then defaultSpecialOfferTransactionOutput

  getTransactionByDeviceIdAndOfferId: (deviceId, offerId) ->
    cknex().select '*'
    .from 'special_offer_transactions_by_deviceId'
    .where 'deviceId', '=', deviceId
    .andWhere 'timeBucket', '=', 'all'
    .andWhere 'offerId', '=', offerId
    .run {isSingle: true}
    .then defaultSpecialOfferTransactionOutput

  upsertTransaction: (transaction, {map} = {}) ->
    transaction = defaultSpecialOfferTransaction transaction

    q = cknex().update 'special_offer_transactions'
    .set _.omit transaction, ['userId', 'timeBucket', 'offerId']

    if map
      _.forEach map, (value, column) ->
        q.add column, value

    qDeviceId = cknex().update 'special_offer_transactions_by_deviceId'
    .set _.omit transaction, ['deviceId', 'timeBucket', 'offerId']

    if map
      _.forEach map, (value, column) ->
        qDeviceId.add column, value

    Promise.all [
      q.where 'userId', '=', transaction.userId
      .andWhere 'timeBucket', '=', transaction.timeBucket
      .andWhere 'offerId', '=', transaction.offerId
      .run()

      qDeviceId.where 'deviceId', '=', transaction.deviceId
      .andWhere 'timeBucket', '=', transaction.timeBucket
      .andWhere 'offerId', '=', transaction.offerId
      .run()
  ]

  upsert: (specialOffer) ->
    specialOffer = defaultSpecialOffer specialOffer

    cknex().update 'special_offers'
    .set _.omit specialOffer, ['timeBucket', 'id']
    .where 'id', '=', specialOffer.id
    .andWhere 'timeBucket', '=', specialOffer.timeBucket
    .run()

module.exports = new SpecialOfferModel()
