_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'

ADDONS_TABLE = 'addons'
CREATOR_ID_INDEX = 'creatorId'
KEY_INDEX = 'key'
SCORE_INDEX = 'score'
ADD_TIME_INDEX = 'addTime'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

FIVE_MINUTE_SECONDS = 60 * 5

# SDK ids. These will eventually be stored in database,
# but hardcoded until then.
# htmldino: 005862d0-a474-4329-9b6d-20cf31c46be0
# t.lombart97: 93d9d6b7-aec2-4ae1-a1a2-b76bb81ddb98
# the1nk: e27297be-ee97-4216-b854-cfc0d15811b5
# tzelon: 18ec096a-0826-458e-8d8e-114ba3292cc2
# king_dragonhoff 9e27a585-794a-42a8-bd8f-98925d7e3fd4
# isaiass18 91835a33-f775-4d5f-8930-476df556c611
# s1032319: cdd55064-2832-421b-96e7-0cb1533a8ff2


defaultAddon = (addon) ->
  unless addon?
    return null

  _.defaults addon, {
    id: uuid.v4()
    creatorId: null
    creator: {}
    key: null
    url: null
    iconUrl: null
    upvotes: 0
    downvotes: 0
    score: 0
    data: {}
    translatedLanguages: null # leave null for all
    supportedLanguages: null # leave null for all
    lastUpdateTime: new Date()
    addTime: new Date()
  }

class AddonModel
  RETHINK_TABLES: [
    {
      name: ADDONS_TABLE
      options: {}
      indexes: [
        {name: CREATOR_ID_INDEX}
        {name: KEY_INDEX}
        {name: SCORE_INDEX}
        {name: ADD_TIME_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (addon) ->
    addon = defaultAddon addon

    r.table ADDONS_TABLE
    .insert addon
    .run()
    .then ->
      addon

  getById: (id, {preferCache} = {}) ->
    get = ->
      r.table ADDONS_TABLE
      .get id
      .run()
      .then defaultAddon

    if preferCache
      key = "#{CacheService.PREFIXES.ADDON_ID}:#{id}"
      CacheService.preferCache key, get, {expireSeconds: FIVE_MINUTE_SECONDS}
    else
      get()


  getByKey: (key, {preferCache} = {}) ->
    get = ->
      r.table ADDONS_TABLE
      .getAll key, {index: KEY_INDEX}
      .nth 0
      .default null
      .run()
      .then defaultAddon

    if preferCache
      cacheKey = "#{CacheService.PREFIXES.ADDON_KEY}:#{key}"
      CacheService.preferCache cacheKey, get, {
        expireSeconds: FIVE_MINUTE_SECONDS
      }
    else
      get()

  getAll: ({preferCache} = {}) ->
    get = ->
      r.table ADDONS_TABLE
      .orderBy {index: r.desc 'score'}
      .run()
      .then (addons) ->
        _.filter addons, (addon) ->
          not addon.isHidden
      .map defaultAddon

    if preferCache
      key = "#{CacheService.KEYS.ADDON_GET_ALL}"
      CacheService.preferCache key, get, {expireSeconds: FIVE_MINUTE_SECONDS}
    else
      get()

  updateById: (id, diff) ->
    r.table ADDONS_TABLE
    .get id
    .update diff
    .run()

  sanitize: _.curry (requesterId, addon) ->
    _.pick addon, [
      'id'
      'key'
      'creatorId'
      'creator'
      'iconUrl'
      'url'
      'myVote'
      'score'
      'upvotes'
      'downvotes'
      'myVote'
      'addTime'
      'supportedLanguages'
      'translatedLanguages'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new AddonModel()
