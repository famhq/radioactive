_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

GROUP_CLANS_TABLE = 'group_clans'
CLAN_ID_GAME_ID_INDEX = 'clanIdGameId'

defaultGroupClan = (groupClan) ->
  unless groupClan?
    return null

  _.defaults groupClan, {
    id: if groupClan?.gameId and groupClan?.clanId \
        then "#{groupClan?.gameId}:#{groupClan?.clanId}"
        else uuid.v4()
    gameId: null
    clanId: null
    groupId: null # can only be tied to 1 group
    mode: 'public'
    password: null
    creatorId: null
    code: module.exports.generateCode()
    playerIds: []
  }

class GroupClan
  RETHINK_TABLES: [
    {
      name: GROUP_CLANS_TABLE
      indexes: []
    }
  ]

  create: (groupClan) ->
    groupClan = defaultGroupClan groupClan

    r.table GROUP_CLANS_TABLE
    .insert groupClan
    .run()
    .then ->
      groupClan

  generateCode: ->
    # no 0 or O (avoid confusion)
    _.sampleSize('ABCDEFGHIJKLMNPQRSTUFWXYZ123456789', 6).join ''

  getById: (id) ->
    r.table GROUP_CLANS_TABLE
    .get id
    .run()
    .then defaultGroupClan

  deleteById: (id) ->
    r.table GROUP_CLANS_TABLE
    .get id
    .delete()
    .run()

  getByClanIdAndGameId: (clanId, gameId) ->
    r.table GROUP_CLANS_TABLE
    .get "#{gameId}:#{clanId}"
    .run()
    .then defaultGroupClan

  updateByClanIdAndGameId: (clanId, gameId, diff) ->
    prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_ID
    groupCacheKey = "#{prefix}:#{clanId}:#{gameId}"
    prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_ID
    cacheKey = "#{prefix}:#{clanId}:#{gameId}"

    r.table GROUP_CLANS_TABLE
    .get "#{gameId}:#{clanId}"
    .update diff
    .run()
    .tap ->
      Promise.all [
        CacheService.deleteByKey cacheKey
        CacheService.deleteByKey groupCacheKey
      ]

  updateByClanIdsAndGameId: (clanIds, gameId, diff) ->
    # TODO: clear cache
    clanIdGameIds = _.map clanIds, (clanId) -> "#{gameId}:#{clanId}"
    r.table GROUP_CLANS_TABLE
    .getAll r.expr(clanIds)
    .update diff
    .run()


module.exports = new GroupClan()
