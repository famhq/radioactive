Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'
moment = require 'moment'

GroupClan = require '../models/group_clan'
Clan = require '../models/clan'
Player = require '../models/player'
User = require '../models/user'
ClanRecord = require '../models/clan_record'
UserRecord = require '../models/user_record'
UserPlayer = require '../models/user_player'
# ClashRoyaleTopClan = require '../models/clash_royale_top_clan'
CacheService = require './cache'
PushNotificationService = require './push_notification'
ClashRoyaleAPIService = require './clash_royale_api'
config = require '../config'

MAX_TIME_TO_COMPLETE_MS = 60 * 30 * 1000 # 30min
CLAN_STALE_TIME_S = 3600 * 12 # 12hr
MIN_TIME_BETWEEN_UPDATES_MS = 60 * 20 * 1000 # 20min
TWENTY_THREE_HOURS_S = 3600 * 23
BATCH_REQUEST_SIZE = 50
GAME_ID = config.CLASH_ROYALE_ID

class ClashRoyaleClan
  formatClan: (clan) ->
    _.pick clan, ['name', 'badge', 'type', 'description', 'trophies',
      'minTrophies', 'donations', 'region']

  formatClanPlayer: (player) ->
    {
      playerId: player.tag
      name: player.name
      trophies: player.trophies
      level: player.level
      arena: player.arena
      league: player.league
      role: player.role
      donations: player.donations
      clanChestCrowns: player.clanChestCrowns
    }

  updateClan: ({userId, clan, tag, isDaily}) =>
    unless tag and clan
      return Promise.resolve null

    players = _.map clan.members, @formatClanPlayer

    diff = {
      lastUpdateTime: new Date()
      clanId: tag
      data: @formatClan clan
      players: players
    }

    Clan.getByClanIdAndGameId tag, GAME_ID
    .then (existingClan) ->
      ClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID
        scaledTime: ClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.donations}
      }

      ClanRecord.upsert {
        clanId: tag
        clanRecordTypeId: config.CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID
        scaledTime: ClanRecord.getScaledTimeByTimeScale 'week'
        diff: {value: clan.trophies}
      }

      playerIds = _.map players, 'playerId'
      Promise.all [
        UserPlayer.getAllByPlayerIdsAndGameId playerIds, GAME_ID
        Player.getAllByPlayerIdsAndGameId playerIds, GAME_ID
      ]
      .then ([existingUserPlayers, existingPlayers]) ->
        _.map existingUserPlayers, (existingUserPlayer) ->
          player = _.find players, {playerId: existingUserPlayer.playerId}
          donations = player.donations
          clanChestCrowns = player.clanChestCrowns
          UserRecord.upsert {
            userId: existingUserPlayer.userId
            gameRecordTypeId: config.CLASH_ROYALE_DONATIONS_RECORD_ID
            scaledTime: UserRecord.getScaledTimeByTimeScale 'week'
            diff: {value: donations, playerId: existingUserPlayer.playerId}
          }
          UserRecord.upsert {
            userId: existingUserPlayer.userId
            gameRecordTypeId: config.CLASH_ROYALE_CLAN_CROWNS_RECORD_ID
            scaledTime: UserRecord.getScaledTimeByTimeScale 'week'
            diff: {
              value: clanChestCrowns, playerId: existingUserPlayer.playerId
            }
          }

        newPlayers = _.filter _.map players, (player) ->
          unless _.find existingPlayers, {id: player.playerId}
            # ClashRoyaleAPIService.updatePlayerById playerId, {
            #   priority: 'normal'
            # }
            # .then ->
            {
              # only set to true when clan is claimed
              # hasUserId: true
              id: player.playerId
              updateFrequency: 'none'
              data:
                name: player.name
                trophies: player.trophies
                level: player.level
                arena: player.arena
                league: player.league
                stats: {}
                splits: {}
                clan:
                  badge: clan.badge
                  name: clan.name
                  tag: tag
            }
        Player.batchCreateByGameId GAME_ID, newPlayers


      (if existingClan
        Clan.updateByClanIdAndGameId tag, GAME_ID, diff
      else
        Clan.createByGameId GAME_ID, _.defaults {id: diff.clanId}, diff
        .then ({id}) ->
          Clan.createGroup {
            userId: userId
            name: clan.name
            clanId: diff.clanId
          }
          .then (group) ->
            GroupClan.updateByClanIdAndGameId tag, GAME_ID, {groupId: group.id}
      ).catch (err) ->
        console.log 'clan err', err

  updateStale: ({force} = {}) ->
    Clan.getStaleByGameId GAME_ID, {
      type: 'data'
      staleTimeS: if force then 0 else CLAN_STALE_TIME_S
    }
    .map ({id}) -> id
    .then (clanIds) ->
      console.log 'staleclan', clanIds.length, new Date()
      Clan.updateByClanIdsAndGameId clanIds, GAME_ID, {
        lastUpdateTime: new Date()
      }
      clanIdChunks = _.chunk clanIds, BATCH_REQUEST_SIZE
      Promise.map clanIdChunks, (clanIds) ->
        tagsStr = clanIds.join ','
        request "#{config.CR_API_URL}/clans/#{tagsStr}", {
          json: true
          qs:
            callbackUrl:
              "#{config.RADIOACTIVE_API_URL}/clashRoyaleAPI/updateClan"
        }
        .catch (err) ->
          console.log 'err staleClan'
          console.log err

  processUpdateClan: ({userId, tag, clan}) =>
    @updateClan {userId, tag, clan}

  # getTopClans: ->
  #   request "#{config.CR_API_URL}/clans/top", {json: true}
  #
  # updateTopClans: =>
  #   if config.ENV is config.ENVS.DEV
  #     return
  #   @getTopClans().then (topClans) =>
  #     Promise.map topClans, (clan, index) =>
  #       rank = index + 1
  #       clanId = clan.clanTag
  #       Clan.getByClanIdAndGameId clanId, GAME_ID
  #       .then (player) =>
  #         if player?.verifiedUserId
  #           Clan.updateById player.id, {
  #             data:
  #               trophies: clan.trophies
  #               name: clan.name
  #           }
  #         else
  #           User.create {}
  #           .then ({id}) =>
  #             userId = id
  #             @updateByClanId clanId, {
  #               userId: userId, priority: 'normal'
  #             }
  #
  #       .then ->
  #         ClashRoyaleTopClan.upsertByRank rank, {
  #           clanId: clanId
  #         }


module.exports = new ClashRoyaleClan()
