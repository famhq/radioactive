_ = require 'lodash'
request = require 'request-promise'
Promise = require 'bluebird'
crypto = require 'crypto'
qs = require 'qs'

config = require '../config'
User = require '../models/user'

KIIP_API_URL = 'https://api.kiip.me/2.0/server'
IRON_SOURCE_API_URL =
  'http://nativeapi.supersonicads.com/delivery/mobilePanel.php'
FYBER_API_URL = 'http://api.fyber.com/feed/v1/offers.json'
ADSCEND_API_URL = 'https://api.adscendmedia.com/v1/publisher'
THIRTY_MINUTES_SECONDS = 30 * 60

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
          }
        ]
    .catch (err) ->
      console.log err

  _getIronSource: (options, {user, headers, connection}) ->
    type = if options.platform is 'iOS' then 'IFA' else 'AID'
    deviceOs = if options.platform is 'iOS' then 'ios' else 'android'
    console.log qs.stringify
      nativeAd: 1
      format: 'json'
      applicationUserId: user.id
      applicationKey: '6876d13d'
      deviceOs: deviceOs
      "deviceIds[#{type}]": options.deviceId
      isLimitAdTrackingEnabled: true
      deviceOSVersion: options.osVersion or 22 # TODO
      ip: options.ip #  TODO need secreteKey to specifcy
      secretKey: config.IRONSOURCE_SECRET_KEY
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
        ip: options.ip #  TODO need secreteKey to specifcy
        secretKey: config.IRONSOURCE_SECRET_KEY
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
          imageUrl: offer.thumbnail.lowres
          title: offer.title
          description: offer.teaser
          instructions: offer.required_actions
          url: offer.link
          amount: offer.payout
          averageSecondsUntilPayout: offer.time_to_payout?.amount
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
        per_page: 30
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
          amount: Math.floor offer.payout * 100
          # averageSecondsUntilPayout: offer.time_to_payout?.amount
        }

  _getNativeX: -> null
  _getTapJoy: -> null

  getAll: (options, {user, headers, connection}) =>
    options.ip = if config.ENV is config.ENVS.DEV \
                 then '213.143.60.43'
                 else headers['x-forwarded-for'] or connection.remoteAddress
    options.deviceId = '400049cd-09dd-4406-a0d9-00f9ea19f8e1' # TODO
    Promise.all [
      @_getKiip options, {user, headers, connection}
      @_getFyber options, {user, headers, connection}
      @_getAdscend options, {user, headers, connection}
      # @_getIronSource options, {user, headers, connection}
    ]
    .then ([kiip, fyber, adscend]) ->
      _.take _.shuffle(_.filter([].concat(kiip, fyber, adscend))), 10
    .catch (err) ->
      console.log err

  processKiip: (req, res) ->
    {content, quantity, transaction_id, user_id, signature} = req.body

    shasum = crypto.createHash 'sha1'
    shasum.update content + quantity + user_id +
                    transaction_id + config.KIIP_API_SECRET

    isValid = shasum.digest('hex') is signature
    console.log isValid
    if isValid
      console.log 'add', user_id, quantity
      User.addFireById user_id, parseInt(quantity)
    res.sendStatus 200

  processIronsource: (req, res) ->
    return res.send 'SOGHUKDBXXA2GG77XX2RSX4QJNELX58Y:OK'
    # TODO
    {sid, uid, amount, _trans_id_} = req.query
    shasum = crypto.createHash 'sha1'
    shasum.update config.FYBER_SECURITY_TOKEN + uid + amount + _trans_id_
    isValid = shasum.digest('hex') is sid

    console.log isValid
    if isValid
      console.log 'add', uid, amount
      User.addFireById uid, parseInt(amount)
    res.sendStatus 200

  processFyber: (req, res) ->
    {sid, uid, amount, _trans_id_} = req.query
    shasum = crypto.createHash 'sha1'
    shasum.update config.FYBER_SECURITY_TOKEN + uid + amount + _trans_id_
    isValid = shasum.digest('hex') is sid

    console.log isValid
    if isValid
      console.log 'add', uid, amount
      User.addFireById uid, parseInt(amount)
    res.sendStatus 200

  processAdscend: (req, res) ->
    {offerId, amount, userId, txnId, hash} = req.query
    shasum = crypto.createHmac 'md5', config.ADSCEND_SECRET_KEY
    shasum.update qs.stringify {offerId, amount, userId, txnId}
    isValid = shasum.digest('hex') is hash

    amount = amount * 100
    if isValid
      console.log 'adscend add', userId, amount
      User.addFireById userId, parseInt(amount)
    res.sendStatus 200


module.exports = new RewardCtrl()
