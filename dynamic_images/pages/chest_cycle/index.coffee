_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'

Page = require '../'
Player = require '../../../models/player'
DynamicImage = require '../../../models/dynamic_image'
ChestCycle = require '../../components/chest_cycle'
s = require '../../components/s'
config = require '../../../config'

PATH = './dynamic_images/images'

IMAGE_KEY = 'crChestCycle'

module.exports = class ChestCyclePage extends Page
  constructor: ({req, res} = {}) ->
    @query = req.query
    @playerId = req.params.playerId

    @$component = new ChestCycle()

  renderHead: -> ''

  setup: =>
    Player.getByPlayerIdAndGameKey @playerId, 'clash-royale'
    .then (player) =>
      unless player
        return {}
      nextChest = _.snakeCase(player.data.upcomingChests?.items[0]?.name)
      superMagicalChestPath = PATH + '/chests/super_magical_chest.png'
      epicChestPath = PATH + '/chests/epic_chest.png'
      legendaryChestPath = PATH + '/chests/legendary_chest.png'
      nextChestPath = PATH + "/chests/#{nextChest}.png"
      poweredByPath = PATH + '/chests/powered_by.png'

      Promise.all [
        Promise.promisify(fs.readFile) superMagicalChestPath
        Promise.promisify(fs.readFile) epicChestPath
        Promise.promisify(fs.readFile) legendaryChestPath

        if nextChest
        then Promise.promisify(fs.readFile) nextChestPath
        else null

        Promise.promisify(fs.readFile) poweredByPath
      ]
      .then (buffers) =>
        [superMagicalChest, epicChest, legendaryChest,
          nextChest, poweredBy] = buffers
        images = {
          superMagicalChest: new Buffer(superMagicalChest).toString('base64')
          epicChest: new Buffer(epicChest).toString('base64')
          legendaryChest: new Buffer(legendaryChest).toString('base64')
          nextChest: new Buffer(nextChest).toString('base64')
          poweredBy: new Buffer(poweredBy).toString('base64')
        }


        {player, @query, images, width: 360, height: 447}
