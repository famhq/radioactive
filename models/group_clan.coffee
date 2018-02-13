_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

GROUP_CLANS_TABLE = 'group_clans'
CLAN_ID_GAME_KEY_INDEX = 'clanIdGameId'

defaultGroupClan = (groupClan) ->
  unless groupClan?
    return null

  if groupClan?.gameKey is 'clash-royale'
    groupClan?.gameKey = config.LEGACY_CLASH_ROYALE_ID
    groupClan?.gameId = config.LEGACY_CLASH_ROYALE_ID

  _.defaults groupClan, {
    id: if groupClan?.gameKey and groupClan?.clanId \
        then "#{groupClan?.gameKey}:#{groupClan?.clanId}"
        else uuid.v4()
    gameKey: null
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

  getByClanIdAndGameKey: (clanId, gameKey) ->
    if gameKey is 'clash-royale'
      gameKey = config.LEGACY_CLASH_ROYALE_ID # FIXME when migrating to scylla
    r.table GROUP_CLANS_TABLE
    .get "#{gameKey}:#{clanId}"
    .run()
    .then defaultGroupClan

  updateByClanIdAndGameKey: (clanId, gameKey, diff) ->
    prefix = CacheService.PREFIXES.GROUP_CLAN_CLAN_ID_GAME_KEY
    groupCacheKey = "#{prefix}:#{clanId}:#{gameKey}"
    prefix = CacheService.PREFIXES.CLAN_CLAN_ID_GAME_KEY
    cacheKey = "#{prefix}:#{clanId}:#{gameKey}"

    r.table GROUP_CLANS_TABLE
    .get "#{gameKey}:#{clanId}"
    .update diff
    .run()
    .tap ->
      Promise.all [
        CacheService.deleteByKey cacheKey
        CacheService.deleteByKey groupCacheKey
      ]

  updateByClanIdsAndGameKey: (clanIds, gameKey, diff) ->
    # TODO: clear cache
    clanIdGameIds = _.map clanIds, (clanId) -> "#{gameKey}:#{clanId}"
    r.table GROUP_CLANS_TABLE
    .getAll r.expr(clanIds)
    .update diff
    .run()


module.exports = new GroupClan()
