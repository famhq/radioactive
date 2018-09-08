_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

ClashRoyaleService = require '../services/game_clash_royale'
FortniteService = require '../services/game_fortnite'
r = require '../services/rethinkdb'
Player = require '../models/player'
User = require '../models/user'
GroupUser = require '../models/group_user'
ClashRoyaleMatch = require '../models/clash_royale_match'
config = require '../config'

HEALTHCHECK_TIMEOUT = 20000
AUSTIN_TAG = '22CJ9CQC0'
AUSTIN_USERNAME = 'austin'
AUSTIN_ID = '0b2884ec-eb4b-432c-807a-f9879a65f0db'


class HealthCtrl
  check: (req, res, next) ->
    Promise.all [
      r.dbList().run().timeout HEALTHCHECK_TIMEOUT

      # Kue.getCount()

      ClashRoyaleService.getPlayerDataByPlayerId AUSTIN_TAG, {
        priority: 'high'
        skipCache: true
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      ClashRoyaleService.getPlayerMatchesByTag AUSTIN_TAG, {
        priority: 'high'
      }
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      # ClashRoyaleService.getPlayerDataByPlayerId AUSTIN_TAG, {
      #   priority: 'high'
      #   skipCache: true
      #   isLegacy: true
      # }
      # .timeout HEALTHCHECK_TIMEOUT
      # .catch -> null

      FortniteService.getPlayerDataByPlayerId 'ps4:starfireaustin', {
        priority: 'high'
        skipCache: true
      }

      Player.getByPlayerIdAndGameKey AUSTIN_TAG, 'clash-royale'
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      GroupUser.getByGroupIdAndUserId config.GROUPS.PLAY_HARD.ID, AUSTIN_ID
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      User.getByUsername AUSTIN_USERNAME
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null

      ClashRoyaleMatch.getAllByPlayerId "#{AUSTIN_TAG}"
      .timeout HEALTHCHECK_TIMEOUT
      .catch -> null
    ]
    .then (responses) ->
      [rethink, apiData, apiMatches, fortnitePlayer,
        player, groupUser, user, matches] = responses
      result =
        rethinkdb: Boolean rethink
        apiData: apiData?.tag is "##{AUSTIN_TAG}"
        apiMatches: Boolean apiMatches
        # legacyApi: apiData?.tag is "##{AUSTIN_TAG}"
        fortnitePlayer: Boolean fortnitePlayer
        scyllaPlayer: player?.id is AUSTIN_TAG
        scyllaMatches: _.isArray matches?.rows
        rethinkUser: user?.username is AUSTIN_USERNAME
        groupUser: "#{groupUser.userId}" is AUSTIN_ID

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
