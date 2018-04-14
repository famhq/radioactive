Promise = require 'bluebird'
_ = require 'lodash'

Group = require '../models/group'
Connection = require '../models/connection'
UserUpgrade = require '../models/user_upgrade'
TwitchService = require '../services/connection_twitch'
CacheService = require '../services/cache'
config = require '../config'

# seems to be more than 31 days
TWITCH_SUB_DAYS = 3600 * 24 * 35

class ConnectionCtrl
  upsert: ({site, token, groupId}, {user}) =>
    Connection.upsert {site, token, userId: user.id}
    .then =>
      if groupId
        @giveUpgradesByGroupId {groupId}, {user}

  getAll: ({}, {user}) ->
    Connection.getAllByUserId user.id

  giveUpgradesByGroupId: ({groupId}, {user}) ->
    Promise.all [
      Group.getById groupId
      Connection.getAllByUserId user.id
    ]
    .then ([group, connections]) ->
      Promise.map connections, (connection) ->
        if connection.site is 'twitch' and group.twitchChannel
          TwitchService.getIsSubscribedToChannelId(
            group.twitchChannel, connection.token
          )
          .then (isSubscribed) ->
            if isSubscribed
              secondsSinceSub = (
                Date.now() - new Date(isSubscribed).getTime()
              ) / 1000
              ttl = Math.floor TWITCH_SUB_DAYS - secondsSinceSub
              UserUpgrade.upsert {
                userId: user.id
                groupId: groupId
                itemKey: 'twitch_sub'
                upgradeType: 'twitchSubBadge'
                data:
                  image: group.badge
              }, {ttl}
              .tap ->
                key = "#{CacheService.PREFIXES.CHAT_USER}:#{user.id}:#{groupId}"
                CacheService.deleteByKey key



module.exports = new ConnectionCtrl()
