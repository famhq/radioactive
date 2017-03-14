_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserGameData = require '../models/user_game_data'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
ClashRoyaleApiService = require '../services/clash_royale_api'
config = require '../config'
schemas = require '../schemas'

defaultEmbed = []

class UserGameDataCtrl
  getMeByGameId: ({gameId}, {user}) ->
    gameId or= config.CLASH_ROYALE_ID

    UserGameData.getByUserIdAndGameId user.id, gameId

module.exports = new UserGameDataCtrl()
