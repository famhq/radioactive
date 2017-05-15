_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'

Page = require '../'
Player = require '../../../models/player'
DynamicImage = require '../../../models/dynamic_image'
ChestCycle = require '../../components/chest_cycle'
s = require '../../components/s'
EmbedService = require '../../services/embed'
config = require '../../../config'

PATH = './dynamic_images/images'

IMAGE_KEY = 'crChestCycle'

module.exports = class ChestCyclePage extends Page
  constructor: ({req, res} = {}) ->
    @query = req.query
    @userId = req.params.userId

    @$component = new ChestCycle()

  renderHead: ({player, images}) ->
    s 'defs',
      s 'pattern', {
        id: 'clanBadgeImage'
        width: 66
        height: 56
      },
        s 'image',
          width: 66
          height: 56
          'xlink:href': "data:image/png;base64,#{images.clanBadge}"
      s 'pattern', {
        id: 'favoriteCardImage'
        width: 66
        height: 88
      },
        s 'image',
          width: 66
          height: 88
          'xlink:href': "data:image/png;base64,#{images.card}"
      s 'pattern', {
        id: 'backgroundImage'
        width: 500
        height: 100
      },
        s 'image',
          width: 500
          height: 100
          'xlink:href': "data:image/png;base64,#{images.background}"

  setup: =>
    embed = EmbedService.TYPES.PLAYER.CHEST_CYCLE
    Player.getByUserIdAndGameId @userId, config.CLASH_ROYALE_ID
    .then EmbedService.embed {embed}
    .then (player) =>
      # TODO

      Promise.all [
        Promise.promisify(fs.readFile) backgroundPath
        Promise.promisify(fs.readFile) cardPath
        Promise.promisify(fs.readFile) clanBadgePath
      ]
      .then ([background, card, clanBadge]) =>
        images = {
          background: new Buffer(background).toString('base64')
          card: new Buffer(card).toString('base64')
          clanBadge: new Buffer(clanBadge).toString('base64')
        }


        {player, @query, images}
