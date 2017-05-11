_ = require 'lodash'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
GroupClan = require './group_clan'
ClashRoyaleClan = require './clash_royale_clan'
config = require '../config'

STALE_INDEX = 'stale'
CLAN_ID_GAME_ID_INDEX = 'clanIdGameId'

DEFAULT_STALE_LIMIT = 80
ONE_DAY_S = 3600 * 24
CODE_LENGTH = 6

class ClanModel
  constructor: ->
    @GameClans =
      "#{config.CLASH_ROYALE_ID}": ClashRoyaleClan

  # TODO: remove after ~June 2017?
  migrate: ({clanId, gameId, groupClanExists}) =>
    console.log 'migrate'
    prefix = CacheService.PREFIXES.CLAN_MIGRATE
    key = "#{prefix}:#{clanId}"
    CacheService.runOnce key, =>
      r.db('radioactive').table('clans')
      .get "#{gameId}:#{clanId}"
      .run()
      .then (oldClan) =>
        if oldClan?.id
          groupClan = {
            id: oldClan.id
            creatorId: oldClan.creatorId
            code: oldClan.code
            groupId: oldClan.groupId
            gameId: oldClan.gameId
            clanId: oldClan.clanId
            playerIds: _.map oldClan.players, 'playerId'
          }

          console.log 'create', groupClanExists
          Promise.all [
            unless groupClanExists
              GroupClan.create groupClan
            @GameClans[gameId].create _.defaults {id: oldClan.clanId}, oldClan
          ]

  getByClanIdAndGameId: (clanId, gameId, {preferCache, retry} = {}) =>
    get = =>
      prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      Promise.all [
        CacheService.preferCache cacheKey, ->
          GroupClan.getByClanIdAndGameId clanId, gameId
        , {ignoreNull: true}

        @GameClans[gameId].getById clanId
      ]
      .then ([groupClan, gameClan]) =>
        if groupClan and gameClan
          _.merge groupClan, gameClan
        else
          @migrate {clanId, gameId, groupClanExists: Boolean groupClan}
          .then =>
            unless retry
              @getByClanIdAndGameId clanId, gameId, {retry: true}
      # .then (clan) ->
      #   if clan
      #     _.defaults {clanId}, clan
      #   else null

    if preferCache
      prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_DAY_S}
    else
      get()

  upsertByClanIdAndGameId: (clanId, gameId, diff) ->
    prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_ID
    cacheKey = "#{prefix}:#{clanId}:#{gameId}"
    CacheService.preferCache cacheKey, ->
      GroupClan.create {clanId, gameId}
    , {ignoreNull: true}
    .then =>
      @GameClans[gameId].upsertById clanId, diff

  updateByClanIdAndGameId: (clanId, gameId, diff) =>
    @GameClans[gameId].updateById clanId, diff

  updateByClanIdsAndGameId: (clanIds, gameId, diff) =>
    @GameClans[gameId].updateAllByIds clanIds, diff

  sanitizePublic: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameId'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'players'
      'isUpdatable'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

  sanitize: _.curry (requesterId, clan) ->
    sanitizedClan = _.pick clan, [
      'id'
      'gameId'
      'clanId'
      'groupId'
      'creatorId'
      'code'
      'data'
      'password'
      'players'
      'isUpdatable'
      'lastUpdateTime'
      'embedded'
    ]
    sanitizedClan

module.exports = new ClanModel()
