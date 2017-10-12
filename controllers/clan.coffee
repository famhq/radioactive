_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
Clan = require '../models/clan'
GroupClan = require '../models/group_clan'
Group = require '../models/group'
Player = require '../models/player'
UserPlayer = require '../models/user_player'
Conversation = require '../models/conversation'
ClashRoyaleClanService = require '../services/clash_royale_clan'
ClashRoyaleAPIService = require '../services/clash_royale_api'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
r = require '../services/rethinkdb'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.CLAN.PLAYERS
  EmbedService.TYPES.CLAN.GROUP
]
groupEmbed = [
  EmbedService.TYPES.CLAN.GROUP
]

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
ONE_MINUTE_SECONDS = 60

class ClanCtrl
  getById: ({id}, {user}) ->
    Clan.getByClanIdAndGameId id, GAME_ID
    .then (clan) ->
      if clan
        return clan
      else
        ClashRoyaleClanService.updateByClanId id, {
          priority: 'normal'
        }
        .then ->
          Clan.getByClanIdAndGameId id, GAME_ID
    .then EmbedService.embed {embed: defaultEmbed}
    .then (clan) ->
      if clan?.creatorId is user.id
        Clan.sanitize null, clan
      else if clan
        Clan.sanitizePublic null, clan
      else
        null

  claimById: ({id}, {user}) ->
    Clan.getByClanIdAndGameId id, GAME_ID
    .then (clan) ->
      unless clan
        router.throw {status: 404, info: 'clan not found'}

      Promise.all [
        ClashRoyaleAPIService.getClanByTag clan.clanId
        Player.getByUserIdAndGameId user.id, GAME_ID
      ]
      .then ([updatedClan, player]) ->
        # replace capital O with 0
        description = updatedClan?.description?.toUpperCase()
        isValid = clan?.code and description?.indexOf(clan?.code) isnt -1
        unless isValid
          router.throw {status: 400, info: 'unable to verify'}

        clanPlayer = _.find clan?.data?.memberList, {tag: "##{player?.id}"}
        isLeader = clanPlayer?.role in ['coLeader', 'leader']
        unless isLeader
          router.throw {status: 400, info: 'must be at least co-leader'}

        Promise.all [
          # reset code so others can't use
          GroupClan.updateByClanIdAndGameId id, GAME_ID, {
            creatorId: user.id
            code: GroupClan.generateCode()
          }
          UserPlayer.setVerifiedByUserIdAndPlayerIdAndGameId(
            user.id
            player.id
            GAME_ID
          )
          Group.updateById clan?.groupId, {creatorId: user.id}
        ]

  updateById: ({id, clanPassword}, {user}) ->
    Clan.getByClanIdAndGameId id, GAME_ID
    .then (clan) ->
      if not clan?.creatorId or clan?.creatorId isnt user.id
        router.throw {status: 401, info: 'invalid permission'}

      unless clanPassword
        router.throw {status: 400, info: 'must specify a password'}

      GroupClan.updateByClanIdAndGameId id, GAME_ID, {password: clanPassword}

  joinById: ({id, clanPassword}, {user}) ->
    Promise.all [
      Clan.getByClanIdAndGameId id, GAME_ID
      .then EmbedService.embed {embed: groupEmbed}

      Player.getByUserIdAndGameId user.id, GAME_ID
    ]
    .then ([clan, player]) ->
      clanPlayer = _.find clan?.data?.memberList, {tag: "##{player?.id}"}
      unless clanPlayer
        router.throw {status: 401, info: 'not a clan member'}

      if not clanPassword or clanPassword isnt clan.password
        router.throw {status: 401, info: 'incorrect password'}

      Promise.all [
        Group.updateById clan.groupId,
          userIds: r.row('userIds').append(user.id).distinct()
        UserPlayer.setVerifiedByUserIdAndPlayerIdAndGameId(
          user.id
          player.id
          GAME_ID
        )
      ]


  search: ({clanId}, {user}) ->
    clanId = clanId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = ClashRoyaleAPIService.isValidTag clanId
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag', ignoreLog: true}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{clanId}"
    CacheService.preferCache key, ->
      Clan.getByPlayerIdAndGameId clanId, config.CLASH_ROYALE_ID
      .then Clan.sanitizePublic
    , {expireSeconds: TWELVE_HOURS_SECONDS}

module.exports = new ClanCtrl()
