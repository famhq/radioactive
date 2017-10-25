_ = require 'lodash'
request = require 'request-promise'
Promise = require 'bluebird'
crypto = require 'crypto'
router = require 'exoid-router'
qs = require 'qs'
uuid = require 'uuid'
semver = require 'semver'

config = require '../config'
User = require '../models/user'
RewardTransaction = require '../models/reward_transaction'
RewardAttempt = require '../models/reward_attempt'
CacheService = require '../services/cache'
TimeService = require '../services/time'

KIIP_API_URL = 'https://api.kiip.me/2.0/server'
IRON_SOURCE_API_URL =
  'http://nativeapi.supersonicads.com/delivery/mobilePanel.php'
FYBER_API_URL = 'http://api.fyber.com/feed/v1/offers.json'
ADSCEND_API_URL = 'https://api.adscendmedia.com/v1/publisher'
THIRTY_MINUTES_SECONDS = 30 * 60
THREE_HOURS_S = 3600 * 3
VIDEO_ADS_PER_COOLDOWN = 3
VIDEO_AD_COOLDOWN_MS = 3600 * 3 * 1000

kiipRequest = (path, body) ->
  ip =
  body = _.defaultsDeep body, {
    app:
      app_key: config.KIIP_API_KEY
      version: '1'
    sdk_version: '2.3.0'
    device:
      lang: 'en'
      locale: 'en_US'
      # manufacturer: 'google'
      # model: 'nexus_5'
      os: 'Android 5.0'
      resolution: '1080x1776'
  }
  request "#{KIIP_API_URL}#{path}", {
    json: true
    method: 'POST'
    body: body
  }

class RewardCtrl
  setup: (options, {user, headers, connection}) ->
    options.deviceId = '400049cd-09dd-4406-a0d9-00f9ea19f8e1' # TODO
    options.ip = if config.ENV is config.ENVS.DEV \
                 then '213.143.60.43' # spain 70.122.23.236
                 else headers['x-forwarded-for'] or connection.remoteAddress

    kiipRequest '/session', {
      connection:
        ip: options.ip
      device:
        id: options.deviceId
        lang: options.language
        density: options.screenDensity
        resolution: options.screenResolution
        locale: options.locale?.replace '-', '_'
        os: "#{options.osName} #{options.osVersion}"
      user:
        userid: user.id
      events:
        [
          id: 'session_start'
          start: (new Date()).toISOString()
        ]
    }

  _getKiip: (options, {user, headers, connection}) ->
    kiipRequest '/moment', {
      connection:
        ip: options.ip
      test: false
      device:
        id: options.deviceId
        lang: options.language
        density: options.screenDensity
        resolution: options.screenResolution
        locale: options.locale?.replace '-', '_'
        os: "#{options.osName} #{options.osVersion}"
      user:
        userid: user.id
      moment:
        id: config.KIIP_MOMENT_ID
    }
    .then (response) ->
      if response.notification
        [
          {
            imageUrl: response.notification.reward_image_url
            title: response.notification.reward_name
            url: response.view.modal.body_url
            amount: response.view.virtual?.virtual_value or 1
            network: 'kiip'
            offerId: "#{response.view.id}"
          }
        ]
    .catch (err) ->
      console.log err

  _getIronSource: (options, {user, headers, connection}) ->
    type = if options.platform is 'iOS' then 'IFA' else 'AID'
    deviceOs = if options.platform is 'iOS' then 'ios' else 'android'
    request IRON_SOURCE_API_URL,
      json: true
      qs:
        nativeAd: 1
        format: 'json'
        applicationUserId: user.id
        applicationKey: '6876d13d'
        deviceOs: deviceOs
        "deviceIds[#{type}]": options.deviceId
        isLimitAdTrackingEnabled: true
        deviceOSVersion: options.osVersion or 22 # TODO
        # ip: options.ip #  TODO need secreteKey to specifcy
        # secretKey: config.IRONSOURCE_SECRET_KEY
    .tap (e) ->
      console.log e
    .catch (e) ->
      console.log e

  _getFyber: (options, {user, headers, connection}) ->
    # TODO: different key, etc... for android/ios/web? or not necessary?
    params =
      appid: config.FYBER_APP_ID
      device_id: options.deviceId
      ip: options.ip
      locale: options.language
      # offer_types: '101,112' # has key breaks with this....
      page: 1
      ps_time: Math.round user.joinTime.getTime() / 1000
      timestamp: Math.round Date.now() / 1000
      uid: user.id

    combined = qs.stringify(params) + '&' + config.FYBER_API_KEY
    shasum = crypto.createHash 'sha1'
    shasum.update combined
    hashkey = shasum.digest 'hex'

    request FYBER_API_URL,
      json: true
      qs: _.defaults params, {hashkey}
    .then (response) ->
      offers = _.filter response.offers, (offer) ->
        isFreeDownload = _.find offer.offer_types, {offer_type_id: 101}
        isQuickReward = offer.time_to_payout?.amount > 0 and
          offer.time_to_payout?.amount < THIRTY_MINUTES_SECONDS
        isFreeDownload or isQuickReward
      _.map offers, (offer) ->
        {
          imageUrl: offer.thumbnail.lowres?.replace 'http:', 'https:'
          title: offer.title
          description: offer.teaser
          instructions: offer.required_actions
          url: offer.link + '&pub0=' + offer.offer_id
          amount: offer.payout
          averageSecondsUntilPayout: offer.time_to_payout?.amount
          network: 'fyber'
          offerId: "#{offer.offer_id}"
        }
    .catch (e) ->
      console.log e

  _getAdscend: (options, {user, headers, connection}) ->
    request
      json: true
      url: "#{ADSCEND_API_URL}/#{config.ADSCEND_PUBLISHER_ID}/offers.json"
      auth:
        user: config.ADSCEND_PUBLISHER_ID
        pass: config.ADSCEND_SECRET_KEY
      qs:
        countries: [user.country?.toUpperCase() or 'US']
        target_system: if options.osName is 'Android' \
                      then [40]
                      else if options.osName is 'iOS'
                      then [50]
                      else [10]
        per_page: 10
        page: 1
    .then (response) ->
      _.map response.offers, (offer) ->
        description = offer.adwall_description
        if offer.name.indexOf('EngageMe.TV') isnt -1
          description += ' (Videos can be skipped)'
        {
          imageUrl: offer.creatives?[0]?.url
          title: offer.name
          description: offer.description
          instructions: description
          url: offer.click_url + '&sub1=' + user.id
          amount: Math.floor offer.payout * 1000
          # averageSecondsUntilPayout: offer.time_to_payout?.amount
          network: 'adscend'
          offerId: "#{offer.offer_id}"
        }

  _rewardedVideosLeft: (userId) ->
    RewardTransaction.getByUserIdAndTimeBucketAndMinTime(
      userId
      TimeService.getScaledTimeByTimeScale('day')
      new Date(Date.now() - VIDEO_AD_COOLDOWN_MS)
    )
    .then (transactions) ->
      rewardedVideoTransactions = _.filter(transactions, {
        network: 'rewardedVideo'
      })?.length or 0
      VIDEO_ADS_PER_COOLDOWN - rewardedVideoTransactions

  _getNativeX: -> null
  _getTapJoy: -> null

  getAll: (options, {user, headers, connection}) =>
    options.ip = if config.ENV is config.ENVS.DEV \
                 then '213.143.60.43'
                 else headers['x-forwarded-for'] or connection.remoteAddress
    # options.deviceId ?= uuid.v4() # TODO: this shouldn't need to happen
    Promise.all [
      @_getKiip options, {user, headers, connection}
      @_getFyber options, {user, headers, connection}
      @_getAdscend options, {user, headers, connection}
      # @_getIronSource options, {user, headers, connection}

      if options.isApp and semver.gte options.appVersion, '1.4.5'
        @_rewardedVideosLeft user.id
      else
        Promise.resolve 0

      RewardAttempt.getAllByTimeBucket(
        TimeService.getScaledTimeByTimeScale('week')
        {preferCache: true}
      )
    ]
    .then ([kiip, fyber, adscend, rewardedVideosLeft, attempts]) ->
      offers = _.map [].concat(kiip, fyber, adscend), (offer) ->
        unless offer
          return false
        attempt = _.find attempts, {
          network: offer.network, offerId: offer.offerId
        }
        if attempt
          attempts = attempt?.attempts
          conversationRate = if attempt.successes \
                             then attempt.successes / attemp.attempts
                             else 0
        else
          conversationRate = null
          attempts = 0
        _.defaults {conversationRate, attempts}, offer
      offers = _.filter offers, (offer) ->
        unless offer
          return false
        {conversationRate, attempts} = offer
        attempts < 100 or conversationRate > 0.01
      offers = _.shuffle offers

      if rewardedVideosLeft > 0
        offers = [{id: 'rewardedVideo', rewardedVideosLeft}].concat offers

      offers = _.take offers, 10

    .catch (err) ->
      console.log err

  _processKiip: ({content, quantity, transaction_id, user_id, signature}) ->
    shasum = crypto.createHash 'sha1'
    shasum.update content + quantity + user_id +
                    transaction_id + config.KIIP_API_SECRET

    isValid = shasum.digest('hex') is signature

    unless isValid
      throw router.throw {status: 400, info: 'invalid kiip'}

    {
      txnId: transaction_id
      userId: user_id
      fireAmount: parseInt(quantity)
      offerId: "#{content}"
    }

    # TODO
  _processIronsource: ({sid, uid, amount, _trans_id_}) ->
    shasum = crypto.createHash 'sha1'
    shasum.update config.FYBER_SECURITY_TOKEN + uid + amount + _trans_id_
    isValid = shasum.digest('hex') is sid

    unless isValid
      throw router.throw {status: 400, info: 'invalid ironsource'}

    {
      userId: uid
      fireAmount: parseInt(amount)
      txnId: _trans_id_
      offerId: 'TODO'
    }

  _processFyber: ({sid, uid, amount, _trans_id_, pub0}) ->
    shasum = crypto.createHash 'sha1'
    shasum.update config.FYBER_SECURITY_TOKEN + uid + amount + _trans_id_
    isValid = shasum.digest('hex') is sid

    # unless isValid
    #   throw router.throw {status: 400, info: 'invalid fyber'}
    console.log 'fyber', uid, amount, _trans_id_, pub0
    {
      userId: uid
      fireAmount: parseInt(amount)
      txnId: _trans_id_
      offerId: "#{pub0}" or ''
    }

  _processAdscend: ({offerId, amount, userId, txnId, hash}) ->
    shasum = crypto.createHmac 'md5', config.ADSCEND_SECRET_KEY
    shasum.update qs.stringify {offerId, amount, userId, txnId}
    isValid = shasum.digest('hex') is hash

    amount = amount * 1000

    unless isValid
      throw router.throw {status: 400, info: 'invalid ascend'}

    console.log 'adscend add', userId, amount
    {userId, txnId, offerId, fireAmount: amount}

  process: (req, res) =>
    network = req.params.network
    {txnId, userId, fireAmount, offerId} = switch network
      when 'kiip' then @_processKiip req.body
      when 'fyber' then @_processFyber req.query
      when 'adscend' then @_processAdscend req.query
      when 'ironsource' then @_processIronsource req.query

    RewardTransaction.getByNetworkAndTxnId network, txnId
    .then (transaction) ->
      if transaction
        router.throw {status: 400, info: 'duplicate'}

      Promise.all [
        RewardTransaction.upsert {
          network, txnId, userId, fireAmount, offerId
        }
        RewardAttempt.incrementByNetworkAndOfferId network, offerId, 'successes'
      ]
    .then ->
      User.addFireById userId, fireAmount

    res.sendStatus 200

  videoReward: ({timestamp, successKey}, {user}) =>
    fireAmount = 1

    shasum = crypto.createHmac 'md5', config.NATIVE_SORT_OF_SECRET
    shasum.update "#{timestamp}"
    compareKey = shasum.digest('hex')
    if compareKey and compareKey is successKey
      @_rewardedVideosLeft user.id
      .then (rewardedVideosLeft) ->
        unless rewardedVideosLeft > 0
          router.throw {status: 400, info: 'none left'}
      .then ->
        RewardTransaction.getByNetworkAndTxnId 'rewardedVideo', "#{timestamp}"
      .then (transaction) ->
        if transaction
          router.throw {status: 400, info: 'duplicate'}

        Promise.all [
          RewardTransaction.upsert {
            network: 'rewardedVideo'
            txnId: "#{timestamp}"
            userId: user.id
            fireAmount: fireAmount
            offerId: "#{timestamp}"
          }
          User.addFireById user.id, fireAmount
        ]

  incrementAttemptsByNetworkAndOfferId: ({network, offerId}, {user}) ->
    prefix = CacheService.PREFIXES.REWARD_INCREMENT
    key = "#{prefix}:#{network}:#{offerId}:#{user.id}"
    CacheService.runOnce key, ->
      RewardAttempt.incrementByNetworkAndOfferId network, offerId, 'attempts'
    , {expireSeconds: THREE_HOURS_S}


module.exports = new RewardCtrl()
