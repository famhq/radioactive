_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
Clan = require '../models/clan'
ClashRoyaleClanService = require '../services/clash_royale_clan'
KueCreateService = require '../services/kue_create'
CacheService = require '../services/cache'
EmbedService = require '../services/embed'
config = require '../config'

defaultEmbed = [EmbedService.TYPES.CLAN.PLAYERS]

GAME_ID = config.CLASH_ROYALE_ID
TWELVE_HOURS_SECONDS = 12 * 3600
ONE_MINUTE_SECONDS = 60

class ClanCtrl
  getById: ({id}, {user}) ->
    Clan.getById id
    .then EmbedService.embed {embed: defaultEmbed}

  search: ({clanId}, {user}) ->
    clanId = clanId.trim().toUpperCase()
                .replace '#', ''
                .replace /O/g, '0' # replace capital O with zero

    isValidTag = clanId.match /^[0289PYLQGRJCUV]+$/
    console.log 'search', clanId
    unless isValidTag
      router.throw {status: 400, info: 'invalid tag'}

    key = "#{CacheService.PREFIXES.PLAYER_SEARCH}:#{clanId}"
    CacheService.preferCache key, ->
      Clan.getByPlayerIdAndGameId clanId, config.CLASH_ROYALE_ID
    , {expireSeconds: TWELVE_HOURS_SECONDS}

module.exports = new ClanCtrl()
