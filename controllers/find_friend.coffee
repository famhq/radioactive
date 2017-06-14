_ = require 'lodash'
router = require 'exoid-router'

FindFriend = require '../models/find_friend'
Player = require '../models/player'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.FIND_FRIEND.USER
  EmbedService.TYPES.FIND_FRIEND.PLAYER
]

GAME_ID = config.CLASH_ROYALE_ID
FIFTEEN_MINUTES_SECONDS = 60 * 15

class FindFriendCtrl
  getAll: ({language}, {user}) ->
    Player.getByUserIdAndGameId user.id, GAME_ID
    .then (player) ->
      console.log player
      FindFriend.getAll {language, trophies: player?.data.trophies or 0}
      .map EmbedService.embed {embed: defaultEmbed, gameId: GAME_ID}

  create: ({link, language}, {user}) ->
    matches = link.match(/token=([a-zA-Z0-9]+)/)
    token = matches?[1]
    unless token
      router.throw status: 400, info: 'Invalid link'

    Player.getByUserIdAndGameId user.id, config.CLASH_ROYALE_ID
    .then (player) ->
      unless player
        router.throw status: 404, info: 'player not found'

      key = "#{CacheService.PREFIXES.FIND_FRIEND_CREATE}:#{player.id}"
      CacheService.runOnce key, ->
        FindFriend.create {
          token
          language
          trophies: player.trophies
          playerId: player.id
          userId: user.id
        }
      , {expireSeconds: FIFTEEN_MINUTES_SECONDS}

module.exports = new FindFriendCtrl()
