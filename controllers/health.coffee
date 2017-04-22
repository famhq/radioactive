_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

ClashRoyaleKueService = require '../services/clash_royale_kue'
r = require '../services/rethinkdb'
config = require '../config'

HEALTHCHECK_TIMEOUT = 60000
AUSTIN_TAG = '22CJ9CQC0'

class HealthCtrl
  check: (req, res, next) ->
    Promise.all [
      r.dbList().run().timeout HEALTHCHECK_TIMEOUT
      # FIXME: back to just 'high' priority
      ClashRoyaleKueService.getPlayerDataByTag AUSTIN_TAG, {
        priority: 'critical'
        skipCache: true
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
      ClashRoyaleKueService.getPlayerMatchesByTag AUSTIN_TAG, {
        priority: 'critical'
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
    ]
    .then ([rethinkdb, playerData, playerMatches]) ->
      result =
        rethinkdb: Boolean rethinkdb
        playerData: playerData?.tag is AUSTIN_TAG
        playerMatches: Boolean playerMatches

      result.healthy = _.every _.values result
      return result
    .then (status) ->
      res.json status
    .catch next

module.exports = new HealthCtrl()
