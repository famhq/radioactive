Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

GroupClan = require '../models/group_clan'
Clan = require '../models/clan'
Player = require '../models/player'
User = require '../models/user'
ClashRoyaleClanRecord = require '../models/clash_royale_clan_record'
ClashRoyalePlayerRecord = require '../models/clash_royale_player_record'
UserPlayer = require '../models/user_player'
# ClashRoyaleTopClan = require '../models/clash_royale_top_clan'
CacheService = require './cache'
ClashRoyaleAPIService = require './clash_royale_api'
PushNotificationService = require './push_notification'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
CLAN_STALE_TIME_S = 3600 * 12 # 12hr
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

class ClashRoyaleClan
  updateClan: ({userId, clan, tag}) ->
    unless tag and clan
      return Promise.resolve null

    diff = {
      lastUpdateTime: new Date()
      clanId: tag
      data: clan
      # players: players
    }

    Clan.getByClanIdAndGameId tag, GAME_ID
    .then (existingClan) ->
      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.donations}
      }

      ClashRoyaleClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        scaledTime: ClashRoyaleClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.trophies}
      }

      playerIds = _.map clan.memberList, ({tag}) -> tag.replace '#', ''
      Promise.all [
        UserPlayer.getAllByPlayerIdsAndGameId playerIds, GAME_ID
        Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      ]
      .then ([existingUserPlayers, existingPlayers]) ->
        _.map existingPlayers, (existingPlayer) ->
          clanPlayer = _.find clan.memberList, {
            tag: "##{existingPlayer.id}"
          }
          donations = clanPlayer.donations
          clanChestCrowns = clanPlayer.clanChestCrowns
          # TODO: batch these
          ClashRoyalePlayerRecord.upsert {
            playerId: existingPlayer.id
            gameRecordTypeId: config.CLASH_ROYALE_DONATIONS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            value: donations
          }
          ClashRoyalePlayerRecord.upsert {
            playerId: existingPlayer.id
            gameRecordTypeId: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
            scaledTime: ClashRoyalePlayerRecord.getScaledTimeByTimeScale 'week'
            value: clanChestCrowns
          }

        newPlayers = _.filter _.map clan.memberList, (player) ->
          unless _.find existingPlayers, {id: player.tag.replace('#', '')}
            {
              id: player.tag.replace '#', ''
              data:
                name: player.name
                trophies: player.trophies
                expLevel: player.expLevel
                arena: player.arena
                clan:
                  badgeId: clan.badgeId
                  name: clan.name
                  tag: clan.tag
            }
        Player.batchUpsertByGameId GAME_ID, newPlayers

      (if existingClan
        Clan.upsertByClanIdAndGameId tag, GAME_ID, diff
      else
        Clan.upsertByClanIdAndGameId tag, GAME_ID, diff
        .then ->
          Clan.createGroup {
            userId: userId
            name: clan.name
            clanId: diff.clanId
          }
          .then (group) ->
            GroupClan.updateByClanIdAndGameId tag, GAME_ID, {groupId: group.id}
      ).catch (err) ->
        console.log 'clan err', err


  updateByClanId: (clanId, {userId, priority} = {}) =>
    ClashRoyaleAPIService.getClanByTag clanId, {priority}
    .then (clan) =>
      @updateClan {userId: userId, tag: clanId, clan}
    .then ->
      Clan.getByClanIdAndGameId clanId, config.CLASH_ROYALE_ID, {
        preferCache: true
      }
      .then (clan) ->
        if clan
          {id: clan?.id}


module.exports = new ClashRoyaleClan()
