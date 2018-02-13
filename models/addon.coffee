_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
CacheService = require '../services/cache'

FIVE_MINUTE_SECONDS = 60 * 5

defaultAddon = (addon) ->
  unless addon?
    return null

  addon.data = JSON.stringify addon.data

  _.defaults addon, {
    id: uuid.v4()
  }

defaultAddonOutput = (addon) ->
  unless addon?
    return null

  addon.id = "#{addon.id}"
  addon.data = try
    JSON.parse addon.data
  catch err
    {}

  addon

tables = [
  {
    name: 'addons_by_gameKey'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      creatorId: 'uuid'
      key: 'text'
      url: 'text'
      gameKey: 'text'
      data: 'text' # json: translatedLanguages, supportedLanguages, iconUrl, ...
    primaryKey:
      partitionKey: ['gameKey']
      clusteringColumns: ['id']
  }
  {
    name: 'addons_by_id'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      creatorId: 'uuid'
      key: 'text'
      url: 'text'
      gameKey: 'text'
      data: 'text' # json: translatedLanguages, supportedLanguages, iconUrl, ...
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
  {
    name: 'addons_by_key'
    keyspace: 'starfire'
    fields:
      id: 'uuid'
      creatorId: 'uuid'
      key: 'text'
      url: 'text'
      gameKey: 'text'
      data: 'text' # json: translatedLanguages, supportedLanguages, iconUrl, ...
    primaryKey:
      partitionKey: ['key']
      clusteringColumns: null
  }
  {
    name: 'addons_counter_by_id'
    fields:
      id: 'uuid'
      upvotes: 'counter'
      downvotes: 'counter'
    primaryKey:
      partitionKey: ['id']
      clusteringColumns: null
  }
]

class AddonModel
  SCYLLA_TABLES: tables

  upsert: (addon) ->
    addon = defaultAddon addon

    Promise.all [
      cknex().update 'addons_by_id'
      .set _.omit addon, ['id']
      .where 'id', '=', addon.id
      .run()

      cknex().update 'addons_by_key'
      .set _.omit addon, ['key']
      .where 'key', '=', addon.key
      .run()

      cknex().update 'addons_by_gameKey'
      .set _.omit addon, ['gameKey', 'id']
      .where 'gameKey', '=', addon.gameKey
      .andWhere 'id', '=', addon.id
      .run()
    ]
    .then ->
      addon

  getByKey: (key, {preferCache, omitCounter} = {}) ->
    get = =>
      cknex().select '*'
      .from 'addons_by_key'
      .where 'key', '=', key
      .run {isSingle: true}
      .then (addon) =>
        (if omitCounter or not addon
        then Promise.resolve(null)
        else @getCounterById addon.id)
        .then (addonCounter) ->
          if omitCounter
            addon
          else
            addonCounter or= {upvotes: 0, downvotes: 0}
            _.defaults addon, addonCounter
      .then defaultAddonOutput

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.ADDON_KEY}:#{key}:#{omitCounter}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: FIVE_MINUTE_SECONDS
      }
    else
      get()

  getCounterById: (id) ->
    cknex().select '*'
    .from 'addons_counter_by_id'
    .where 'id', '=', id
    .run {isSingle: true}

  getById: (id, {preferCache, omitCounter} = {}) ->
    get = =>
      Promise.all [
        cknex().select '*'
        .from 'addons_by_id'
        .where 'id', '=', id
        .run {isSingle: true}

        if omitCounter then Promise.resolve(null) else @getCounterById id
      ]
      .then ([addon, addonCounter]) ->
        if omitCounter
          addon
        else
          addonCounter or= {upvotes: 0, downvotes: 0}
          _.defaults addon, addonCounter
      .then defaultAddonOutput

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.ADDON_ID}:#{id}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: FIVE_MINUTE_SECONDS
      }
    else
      get()

  getAllByGameKey: (gameKey, {skip, limit, preferCache} = {}) ->
    skip ?= 0
    limit ?= 50
    get = ->
      prefix = CacheService.STATIC_PREFIXES.ADDON_GAME_KEY_LEADERBOARD_ALL
      cacheKey = "#{prefix}:#{gameKey}"

      Promise.all [
        cknex().select '*'
        .from 'addons_by_gameKey'
        .where 'gameKey', '=', gameKey
        .run()
        .map defaultAddonOutput

        CacheService.leaderboardGet cacheKey, {skip, limit}
      ]
      .then ([addons, addonLeaderboard]) ->
        addonLeaderboard = _.chunk(addonLeaderboard, 2)
        addons = _.filter addons, (addon) ->
          not addon.data.isHidden
        addons = _.orderBy addons, (addon) ->
          leaderboardScore = _.find(addonLeaderboard, ([id, score]) ->
            id is addon.id
          )
          if leaderboardScore then parseInt(leaderboardScore[1]) else 0

        , 'desc'

    if preferCache
      prefix = CacheService.PREFIXES.ADDON_GET_ALL_BY_GAME_KEY
      key = "#{prefix}:#{gameKey}:#{skip}:#{limit}"
      CacheService.preferCache key, get, {expireSeconds: FIVE_MINUTE_SECONDS}
    else
      get()

  incrementByAddon: (addon, diff) ->
    prefix = CacheService.STATIC_PREFIXES.ADDON_GAME_KEY_LEADERBOARD_ALL
    cacheKey = "#{prefix}:#{addon.gameKey}"
    amount = if diff.upvotes is 1 then 1 else -1
    CacheService.leaderboardIncrement cacheKey, addon.id, amount

    q = cknex().update 'addons_counter_by_id'
    _.forEach diff, (amount, key) ->
      q = q.increment key, amount
    q.where 'id', '=', addon.id
    .run()

  migrateAll: =>
    CacheService = require '../services/cache'
    r = require '../services/rethinkdb'
    start = Date.now()
    Promise.all [
      CacheService.get 'migrate_addons_min_id01'
      .then (minId) =>
        minId ?= '0000'
        r.table 'addons'
        .between minId, 'zzzz'
        .orderBy {index: r.asc('id')}
        .limit 500
        .then (addons) =>
          Promise.map addons, (addon) =>
            addon.data ?= {}
            addon.data.translatedLanguages = addon.translatedLanguages
            addon.data.supportedLanguages = addon.supportedLanguages
            addon.data.iconUrl = addon.iconUrl
            addon.data.creatorName = addon.creator.name
            addon.gameKey = 'clash-royale'
            upvotes = addon.upvotes
            downvotes = addon.downvotes
            addon = _.pick addon, ['id', 'creatorId', 'key', 'url', 'data', 'gameKey']
            @incrementByAddon addon, {upvotes, downvotes}
            console.log 'up', addon
            # @upsert addon
          .catch (err) ->
            console.log err
          .then ->
            console.log 'migrate time', Date.now() - start, minId, _.last(addons)?.id
            CacheService.set 'migrate_addons_min_id01', _.last(addons)?.id
            .then ->
              _.last(addons)?.id
    ]


  sanitize: _.curry (requesterId, addon) ->
    _.pick addon, [
      'id'
      'key'
      'creatorId'
      'data'
      'url'
      'myVote'
      'score'
      'upvotes'
      'downvotes'
      'myVote'
      'supportedLanguages'
      'translatedLanguages'
      'embedded'
    ]

module.exports = new AddonModel()
# module.exports.migrateAll()
