_ = require 'lodash'
router = require 'exoid-router'
Joi = require 'joi'

User = require '../models/user'
UserGameData = require '../models/user_game_data'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
config = require '../config'
schemas = require '../schemas'

defaultEmbed = []

class UserGameDataCtrl
  getMeByGameId: ({gameId}, {user}) ->
    gameId or= config.CLASH_ROYALE_ID

    UserGameData.getByUserIdAndGameId user.id, gameId

  updateMeByGameId: ({gameId, diff}, {user}) ->
    gameId or= config.CLASH_ROYALE_ID

    updateDiff = {}

    diff = _.pick diff, ['playerId']

    if diff.playerId
      updateDiff.playerId = diff.playerId
      delete diff.playerId

    updateDiff.data = diff

    UserGameData.upsertByUserIdAndGameId user.id, gameId, updateDiff


module.exports = new UserGameDataCtrl()
