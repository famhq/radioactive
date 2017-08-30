_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

honeypot = require('project-honeypot')(config.HONEYPOT_ACCESS_KEY)
# torIps = (require '../resources/data/tor_ips').split('\n')

defaultBan = (ban) ->
  unless ban?
    return null

  _.defaults ban, {
    id: uuid.v4()
    ip: null
    groupId: null
    userId: null
    duration: '24h'
    scope: 'site'
    time: new Date()
  }

BANS_TABLE = 'bans'
IP_INDEX = 'ip'
USER_ID_INDEX = 'userId'
FILTER_INDEX = 'filter'
TIME_INDEX = 'time'

ONE_DAY_SECONDS = 3600 * 24
ONE_MONTH_SECONDS = 3600 * 24 * 31

class BanModel
  RETHINK_TABLES: [
    {
      name: BANS_TABLE
      indexes: [
        {name: IP_INDEX}
        {name: USER_ID_INDEX}
        {
          name: FILTER_INDEX
          fn: (row) -> [row('groupId'), row('duration'), row('scope')]
        }
        {name: TIME_INDEX}
      ]
    }
  ]

  create: (ban) ->
    ban = defaultBan ban

    r.table BANS_TABLE
    .insert ban
    .run()
    .then ->
      if ban.userId
        key = "#{CacheService.PREFIXES.BAN_USER_ID}:#{ban.userId}"
        CacheService.deleteByKey key
      if ban.ip
        key = "#{CacheService.PREFIXES.BAN_IP}:#{ban.ip}"
        CacheService.deleteByKey key
      ban

  unbanTemp: ->
    # TODO: optimize w/ index
    r.table BANS_TABLE
    .filter r.row('duration').eq('24h').and(
      r.row('time').lt r.now().sub ONE_DAY_SECONDS
    )
    .delete()

  isHoneypotBanned: (ip, {preferCache} = {}) ->
    get = ->
      # Promise.resolve torIps.indexOf(ip) isnt -1
      new Promise (resolve, reject) ->
        honeypot.query ip, (err, payload) ->
          console.log ip, payload
          if err
            resolve false
          else
            isBanned = payload?.type?.spammer
            resolve isBanned

    if preferCache
      key = "#{CacheService.PREFIXES.HONEY_POT_BAN_IP}:#{ip}"
      CacheService.preferCache key, get, {expireSeconds: ONE_MONTH_SECONDS}
    else
      get()

  getAll: ({groupId, duration, scope}) ->
    r.table BANS_TABLE
    .getAll [groupId, duration, scope], {index: FILTER_INDEX}
    .orderBy r.desc 'time'
    .limit 30
    .run()
    .map defaultBan

  getByIp: (ip, {scope, preferCache} = {}) ->
    scope ?= 'chat'

    get = ->
      r.table BANS_TABLE
      .getAll ip, {index: IP_INDEX}
      .filter {scope}
      .nth 0
      .default null
      .run()
      .then defaultBan

    if preferCache
      key = "#{CacheService.PREFIXES.BAN_IP}:#{ip}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  getByUserId: (userId, {scope, preferCache} = {}) ->
    scope ?= 'chat'

    get = ->
      r.table BANS_TABLE
      .getAll userId, {index: USER_ID_INDEX}
      .filter {scope}
      .nth 0
      .default null
      .run()
      .then defaultBan

    if preferCache
      key = "#{CacheService.PREFIXES.BAN_USER_ID}:#{userId}"
      CacheService.preferCache key, get, {expireSeconds: ONE_DAY_SECONDS}
    else
      get()

  deleteAllByIp: (ip) ->
    r.table BANS_TABLE
    .getAll ip, {index: IP_INDEX}
    .delete()
    .run()
    .then ->
      key = "#{CacheService.PREFIXES.BAN_IP}:#{ip}"
      CacheService.deleteByKey key
    .then -> null

  deleteAllByUserId: (userId) ->
    r.table BANS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .delete()
    .run()
    .then ->
      key = "#{CacheService.PREFIXES.BAN_USER_ID}:#{userId}"
      CacheService.deleteByKey key
    .then -> null

module.exports = new BanModel()
