_ = require 'lodash'

uuid = require 'node-uuid'

CacheService = require '../services/cache'
cknex = require '../services/cknex'
config = require '../config'

honeypot = require('project-honeypot')(config.HONEYPOT_ACCESS_KEY)

defaultBan = (ban) ->
  unless ban?
    return null

  _.defaults ban, {
    ip: ''
    timeUuid: cknex.getTimeUuid()
  }

ONE_DAY_SECONDS = 3600 * 24
ONE_MONTH_SECONDS = 3600 * 24 * 31

tables = [
  {
    name: 'bans_by_userId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      bannedById: 'uuid'
      duration: 'text'
      ip: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['userId']
  }
  {
    name: 'bans_by_ip'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      bannedById: 'uuid'
      duration: 'text'
      ip: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['ip']
  }
  {
    name: 'bans_by_duration_and_timeUuid'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      userId: 'uuid'
      bannedById: 'uuid'
      duration: 'text'
      ip: 'text'
      timeUuid: 'timeuuid'
    primaryKey:
      partitionKey: ['groupId', 'duration']
      clusteringColumns: ['timeUuid']
    withClusteringOrderBy: ['timeUuid', 'desc']
  }
]

class BanModel
  SCYLLA_TABLES: tables

  upsert: (ban, {ttl} = {}) ->
    ban = defaultBan ban

    console.log 'upsert', ban

    queries = [
      cknex().update 'bans_by_userId'
      .set _.omit ban, [
        'groupId', 'userId'
      ]
      .where 'groupId', '=', ban.groupId
      .andWhere 'userId', '=', ban.userId

      cknex().update 'bans_by_ip'
      .set _.omit ban, [
        'groupId', 'ip'
      ]
      .where 'groupId', '=', ban.groupId
      .andWhere 'ip', '=', ban.ip

      cknex().update 'bans_by_duration_and_timeUuid'
      .set _.omit ban, [
        'groupId', 'duration', 'timeUuid'
      ]
      .where 'groupId', '=', ban.groupId
      .andWhere 'duration', '=', ban.duration
      .andWhere 'timeUuid', '=', ban.timeUuid
    ]

    if ttl
      queries = _.map queries, (query) ->
        query.usingTTL ttl

    Promise.all _.map queries, (query) ->
      query.run()
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
      if ip?.match('74.82.60')
        return Promise.resolve true
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

  getAllByGroupIdAndDuration: (groupId, duration) ->
    console.log groupId, duration
    cknex().select '*'
    .from 'bans_by_duration_and_timeUuid'
    .where 'groupId', '=', groupId
    .andWhere 'duration', '=', duration
    .run()
    .map defaultBan

  getByGroupIdAndIp: (groupId, ip, {scope, preferCache} = {}) ->
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

  getByGroupIdAndUserId: (groupId, userId, {preferCache} = {}) ->
    get = ->
      cknex().select '*'
      .from 'bans_by_userId'
      .where 'groupId', '=', groupId
      .andWhere 'userId', '=', userId
      .run {isSingle: true}
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
