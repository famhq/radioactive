_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

ClashRoyaleAPIService = require '../services/clash_royale_api'
r = require '../services/rethinkdb'
Player = require '../models/player'
User = require '../models/user'
ClashRoyaleMatch = require '../models/clash_royale_match'
config = require '../config'

HEALTHCHECK_TIMEOUT = 20000
AUSTIN_TAG = '22CJ9CQC0'
AUSTIN_USERNAME = 'austin'


class HealthCtrl
  check: (req, res, next) ->
    Promise.all [
      r.dbList().run().timeout HEALTHCHECK_TIMEOUT

      # Kue.getCount()

      ClashRoyaleAPIService.getPlayerDataByTag AUSTIN_TAG, {
        priority: 'high'
        skipCache: true
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      ClashRoyaleAPIService.getPlayerMatchesByTag AUSTIN_TAG, {
        priority: 'high'
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      ClashRoyaleAPIService.getPlayerDataByTag AUSTIN_TAG, {
        priority: 'high'
        skipCache: true
        isLegacy: true
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      Player.getByPlayerIdAndGameId AUSTIN_TAG, config.CLASH_ROYALE_ID
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      User.getByUsername AUSTIN_USERNAME
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      ClashRoyaleMatch.getAllByPlayerId "#{AUSTIN_TAG}"
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
    ]
    .then ([rethink, apiData, apiMatches, legacyApi, player, user, matches]) ->
      result =
        rethinkdb: Boolean rethink
        apiData: apiData?.tag is "##{AUSTIN_TAG}"
        apiMatches: Boolean apiMatches
        legacyApi: apiData?.tag is "##{AUSTIN_TAG}"
        scyllaPlayer: player?.id is AUSTIN_TAG
        scyllaMatches: _.isArray matches?.rows
        rethinkUser: user?.username is AUSTIN_USERNAME

      result.healthy = _.every _.values result
      return result
    .then (status) ->
      res.json status
    .catch next

  checkThrow: (req, res, next) ->
    r.dbList().run()
    .then (rethinkdb) ->
      if Boolean rethinkdb
        res.send 'ok'
      else
        throw new Error 'rethink unhealthy'
    .catch ->
      # pod will restart from kubernetes probe
      res.status(400).send 'fail'

module.exports = new HealthCtrl()
