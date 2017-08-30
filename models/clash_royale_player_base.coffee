_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
knex = require '../services/knex'
CacheService = require '../services/cache'
config = require '../config'

# FIXME: FIXME: make sure these work with new API before turning back on
# so far can handle 20k per minute (1.2m per hour)
DEFAULT_PLAYER_MATCHES_STALE_LIMIT = 0
# 1,000 players per minute = ~1.4m per day
DEFAULT_PLAYER_DATA_STALE_LIMIT = 0
SIX_HOURS_S = 3600 * 6

fields = [
  {name: 'id', type: 'string', length: 20, index: 'primary'}
  {name: 'updateFrequency', type: 'string', length: 20, defaultValue: 'default'}
  {name: 'data', type: 'json'}
  {name: 'lastQueuedTime', type: 'dateTime', defaultValue: new Date()}
  {name: 'lastDataUpdateTime', type: 'dateTime', defaultValue: new Date()}
  {name: 'lastMatchesUpdateTime', type: 'dateTime', defaultValue: new Date()}
]

defaultPlayer = (player) ->
  unless player?
    return null

  player = _.pick player, _.map(fields, 'name')

  _.defaults player, _.reduce(fields, (obj, field) ->
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

class ClashRoyalePlayerBaseModel
  TABLE_NAME: 'players'

  constructor: ->
    @POSTGRES_TABLES = [
      {
        tableName: @TABLE_NAME
        fields: fields
        indexes: [
          {columns: ['updateFrequency', 'lastMatchesUpdateTime']}
          {columns: ['updateFrequency', 'lastDataUpdateTime']}
        ]
      }
  ]

  batchCreate: (players) =>
    players = _.map players, defaultPlayer

    knex(@TABLE_NAME).insert(players)

  create: (player) =>
    knex(@TABLE_NAME).insert defaultPlayer player

  getById: (id, {preferCache} = {}) =>
    get = =>
      knex @TABLE_NAME
      .first '*'
      .where {id}
      .then defaultPlayer

    if preferCache
      prefix = CacheService.PREFIXES.PLAYER_CLASH_ROYALE_ID
      cacheKey = "#{prefix}:#{id}"
      CacheService.preferCache cacheKey, get, {expireSeconds: SIX_HOURS_S}
    else
      get()

  getAllByIds: (ids, {preferCache} = {}) =>
    knex @TABLE_NAME
    .whereIn 'id', ids
    .map defaultPlayer

  updateAllByIds: (ids, diff) =>
    if @TABLE_NAME is 'players' and diff.data and not diff.data.trophies
      throw new Error 'player updateall missing trophies'

    knex @TABLE_NAME
    .whereIn 'id', ids
    .update diff

  updateById: (id, diff) =>
    diff = _.pick diff, _.map(fields, 'name')

    if @TABLE_NAME is 'players' and diff.data and not diff.data.trophies
      throw new Error 'player update missing trophies'

    if diff.data
      # json has weird bugs if not stringified
      diff.data = JSON.stringify diff.data
    knex @TABLE_NAME
    .where {id}
    .limit 1
    .update diff
    .then defaultPlayer

  upsertById: (id, diff) =>
    if @TABLE_NAME is 'players' and diff.data and not diff.data.trophies
      throw new Error 'player upsert missing trophies'

    if diff.data
      # json has weird bugs if not stringified
      diff.data = JSON.stringify diff.data
    diff = defaultPlayer _.defaults(_.clone(diff), {id})

    upsert {
      table: @TABLE_NAME
      diff: diff
      constraint: '(id)'
    }

  getStale: ({staleTimeS, type, limit}) =>
    if type is 'matches'
      field = 'lastMatchesUpdateTime'
      limit ?= DEFAULT_PLAYER_MATCHES_STALE_LIMIT
    else
      field = 'lastDataUpdateTime'
      limit ?= DEFAULT_PLAYER_DATA_STALE_LIMIT

    console.log 'gt', new Date(Date.now() - staleTimeS * 1000)
    knex @TABLE_NAME
    .where {updateFrequency: 'default'}
    .andWhere field, '<', new Date(Date.now() - staleTimeS * 1000)
    .limit limit
    .map defaultPlayer

  deleteById: (id) =>
    if id
      @upsertById id, {data: {splits: {}}}
      # not sure why delete doesn't work. TODO
      # knex(@TABLE_NAME).where({id}).delete()
    else
      Promise.resolve null


module.exports = ClashRoyalePlayerBaseModel
