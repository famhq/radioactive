_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

STALE_INDEX = 'stale'
CLAN_ID_GAME_ID_INDEX = 'clanIdGameId'

DEFAULT_STALE_LIMIT = 80
ONE_DAY_S = 3600 * 24

defaultClan = (clan) ->
  unless clan?
    return null

  _.defaults clan, {
    id: if clan?.gameId and clan?.clanId \
        then "#{clan?.gameId}:#{clan?.clanId}"
        else uuid.v4()
    gameId: null
    clanId: null
    groupId: null # can only be tied to 1 group
    data:
      stats: {}
    players: []
    lastUpdateTime: new Date()
  }

CLANS_TABLE = 'clans'

class ClanModel
  RETHINK_TABLES: [
    {
      name: CLANS_TABLE
      indexes: [
        {name: STALE_INDEX, fn: (row) ->
          [
            row('gameId')
            row('lastUpdateTime')
          ]
        }
        {name: CLAN_ID_GAME_ID_INDEX, fn: (row) ->
          [row('clanId'), row('gameId')]}
      ]
    }
  ]

  getById: (id) ->
    r.table CLANS_TABLE
    .get id
    .run()
    .then defaultClan

  getByClanIdAndGameId: (clanId, gameId, {preferCache} = {}) ->
    get = ->
      r.table CLANS_TABLE
      .getAll [clanId, gameId], {index: CLAN_ID_GAME_ID_INDEX}
      .nth 0
      .default null
      .run()
      .then defaultClan
      .then (clan) ->
        if clan
          _.defaults {clanId}, clan
        else null

    if preferCache
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      CacheService.preferCache cacheKey, get, {expireSeconds: ONE_DAY_S}
    else
      get()



  upsertByClanIdAndGameId: (clanId, gameId, diff, {userId} = {}) ->
    r.table CLANS_TABLE
    .getAll [clanId, gameId], {index: CLAN_ID_GAME_ID_INDEX}
    .nth 0
    .default null
    .do (clan) ->
      r.branch(
        clan.eq null

        r.table CLANS_TABLE
        .insert defaultClan _.defaults _.clone(diff), {
          clanId
          gameId
        }

        r.table CLANS_TABLE
        .getAll [clanId, gameId], {index: CLAN_ID_GAME_ID_INDEX}
        .nth 0
        .default null
        .update diff
      )
    .run()
    .then ->
      prefix = CacheService.PREFIXES.CLASH_ROYALE_CLAN_CLAN_ID_GAME_ID
      cacheKey = "#{prefix}:#{clanId}:#{gameId}"
      CacheService.deleteByKey cacheKey

  getStaleByGameId: (gameId, {staleTimeS, type, limit}) ->
    index = STALE_INDEX
    limit ?= DEFAULT_STALE_LIMIT
    r.table CLANS_TABLE
    .between(
      [gameId, false, true, 0]
      [gameId, false, true, r.now().sub(staleTimeS)]
      {index}
    )
    .limit limit
    .run()
    .map defaultClan

module.exports = new ClanModel()
