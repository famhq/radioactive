_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
cknex = require '../services/cknex'
CacheService = require '../services/cache'
config = require '../config'

SIX_HOURS_S = 3600 * 6

tables = [
  {
    name: 'clans_by_id'
    keyspace: 'clash_royale'
    fields:
      id: 'text'
      data: 'text'
      lastUpdateTime: 'timestamp'
      lastQueuedTime: 'timestamp'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
  # {
  #   name: 'auto_refresh_clanIds'
  #   fields:
  #     bucket: 'text'
  #     # playerIds overwhelmingly start with '2', but the last character is
  #     # evenly distributed
  #     reversedClanId: 'text'
  #     clanId: 'text'
  #   primaryKey:
  #     partitionKey: ['bucket']
  #     clusteringColumns: ['reversedClanId']
  # }
]

defaultClan = (clan) ->
  unless clan?
    return null

  clan.data = if clan.data then JSON.parse clan.data else {}
  clan

class ClashRoyaleClan
  SCYLLA_TABLES: tables

  getById: (id, {preferCache} = {}) ->
    get = ->
      cknex('clash_royale').select '*'
      .where 'id', '=', id
      .from 'clans_by_id'
      .run {isSingle: true}
      .then defaultClan

    if preferCache
      prefix = CacheService.PREFIXES.CLAN_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) ->
    cknex('clash_royale').select '*'
    .where 'id', 'in', ids
    .from 'clans_by_id'
    .run()
    .map defaultClan

  upsertById: (id, diff) ->
    if typeof diff.data is 'object'
      diff.data = JSON.stringify diff.data

    cknex('clash_royale').update 'clans_by_id'
    .set _.omit(diff, ['clanId'])
    .where 'id', '=', id
    .run()

module.exports = new ClashRoyaleClan()
