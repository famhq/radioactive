_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
knex = require '../services/knex'
CacheService = require '../services/cache'
config = require '../config'

DEFAULT_STALE_LIMIT = 500
SIX_HOURS_S = 3600 * 6

fields = [
  {name: 'id', type: 'string', length: 20, index: 'primary'}
  {name: 'updateFrequency', type: 'string', length: 20, defaultValue: 'default'}
  {name: 'data', type: 'json'}
  {name: 'players', type: 'json'}
  {name: 'lastQueuedTime', type: 'dateTime', defaultValue: new Date()}
  {name: 'lastUpdateTime', type: 'dateTime', defaultValue: new Date()}
]

defaultClan = (clan) ->
  unless clan?
    return null

  clan = _.pick clan, _.map(fields, 'name')

  _.defaults clan, _.reduce(fields, (obj, field) ->
    {name, defaultValue} = field
    if typeof defaultValue is 'function'
      obj[name] = defaultValue()
    else if defaultValue?
      obj[name] = defaultValue
    obj
  , {})

upsert = ({table, diff, constraint}) ->
  insert = knex(table).insert(diff)
  update = knex.queryBuilder().update(diff)

  knex.raw "? ON CONFLICT #{constraint} DO ? returning *", [insert, update]
  .then (result) -> result.rows[0]

class ClashRoyaleClan
  TABLE_NAME: 'clans'

  constructor: ->
    @POSTGRES_TABLES = [
      {
        tableName: @TABLE_NAME
        fields: fields
        indexes: [
          {columns: ['updateFrequency', 'lastMatchesUpdateTime']}
          {columns: ['updateFrequency', 'lastDataupdateTime']}
        ]
      }
  ]

  batchCreate: (clans) =>
    clans = _.map clans, defaultClan

    knex(@TABLE_NAME).insert(clans)

  create: (clan) =>
    if clan.data
      # json has weird bugs if not stringified
      clan.data = JSON.stringify clan.data
    if clan.players
      # json has weird bugs if not stringified
      clan.players = JSON.stringify clan.players
    knex(@TABLE_NAME).insert defaultClan clan

  getById: (id, {preferCache} = {}) =>
    get = =>
      knex @TABLE_NAME
      .first '*'
      .where {id}
      .then defaultClan

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) =>
    knex @TABLE_NAME
    .whereIn 'id', ids
    .map defaultClan

  updateAllByIds: (ids, diff) =>
    knex @TABLE_NAME
    .whereIn 'id', ids
    .update diff

  updateById: (id, diff) =>
    diff = _.pick diff, _.map(fields, 'name')

    if diff.data
      # json has weird bugs if not stringified
      diff.data = JSON.stringify diff.data
    if diff.players
      # json has weird bugs if not stringified
      diff.players = JSON.stringify diff.players

    knex @TABLE_NAME
    .where {id}
    .limit 1
    .update diff
    .then defaultClan

  upsertById: (id, diff) =>
    if diff.data
      # json has weird bugs if not stringified
      diff.data = JSON.stringify diff.data
    if diff.players
      # json has weird bugs if not stringified
      diff.players = JSON.stringify diff.players
    diff = defaultClan _.defaults(_.clone(diff), {id})

    upsert {
      table: @TABLE_NAME
      diff: diff
      constraint: '(id)'
    }

  getStale: ({staleTimeS, type, limit}) =>
    field = 'lastUpdateTime'
    limit ?= DEFAULT_STALE_LIMIT

    knex @TABLE_NAME
    .where field, '<', new Date(Date.now() - staleTimeS * 1000)
    .limit limit
    .map defaultClan

  deleteById: (id) =>
    knex @TABLE_NAME
    .where {id}
    .limit 1
    .delete()


module.exports = new ClashRoyaleClan()
