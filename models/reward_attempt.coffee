_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'
moment = require 'moment'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

defaultRewardAttempt = (rewardAttempt) ->
  unless rewardAttempt?
    return null

  _.defaults rewardAttempt, {
    # 10-17-2017
    timeBucket: 'WEEK-' + moment().format 'YYYY-WW'
    timeUuid: cknex.getTimeUuid()
  }


tables = [
  {
    name: 'reward_attempts_counter_by_offerId'
    keyspace: 'starfire'
    fields:
      network: 'text'
      offerId: 'text'
      attempts: 'counter'
      successes: 'counter'
      # fireAmount: 'int'
      timeBucket: 'text'
    primaryKey:
      partitionKey: ['timeBucket']
      clusteringColumns: ['network', 'offerId']
  }
]

ONE_HOUR_S = 3600

class RewardAttemptModel
  SCYLLA_TABLES: tables

  incrementByNetworkAndOfferId: (network, offerId, field = 'attempts') ->
    rewardAttempt = defaultRewardAttempt {network, offerId}

    cknex().update 'reward_attempts_counter_by_offerId'
    .increment field, 1
    .where 'network', '=', rewardAttempt.network
    .andWhere 'timeBucket', '=', rewardAttempt.timeBucket
    .andWhere 'offerId', '=', rewardAttempt.offerId
    .run()
    .then ->
      rewardAttempt

  getAllByTimeBucket: (timeBucket, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .from 'reward_attempts_counter_by_offerId'
      .where 'timeBucket', '=', timeBucket
      .run()

    if preferCache
      prefix = CacheService.PREFIXES.REWARD_ATTEMPT_TIME
      cacheKey = "#{prefix}:#{timeBucket}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_HOUR_S}
    else
      get()


module.exports = new RewardAttemptModel()
