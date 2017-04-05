_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'

Page = require '../'
UserGameData = require '../../../models/user_game_data'
DynamicImage = require '../../../models/dynamic_image'
ForumSig = require '../../components/forum_sig'
s = require '../../components/s'
config = require '../../../config'

PATH = './dynamic_images/images'

IMAGE_KEY = 'crForumSig'

module.exports = class ForumSigPage extends Page
  constructor: ({req, res} = {}) ->
    @query = req.query
    @userId = req.params.userId

    @$component = new ForumSig()

  renderHead: ({userGameData, images}) ->
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
    Promise.all [
      UserGameData.getByUserIdAndGameId @userId, config.CLASH_ROYALE_ID
      DynamicImage.getByUserIdAndImageKey @userId, IMAGE_KEY
    ]
    .then ([userGameData, dynamicImage]) =>
      color = dynamicImage?.data?.color or 'red'
      favoriteCard = dynamicImage?.data?.favoriteCard or 'sparky'
      console.log userGameData.data?.clan
      badge = userGameData?.data?.clan?.badge or 0
      badge %= 1000
      backgroundPath = PATH + "/forum_signature/background_#{color}.png"
      cardPath = PATH + "/cards/#{favoriteCard}_small.png"
      clanBadgePath = PATH + "/badges/#{badge}.png"

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


        {userGameData, @query, images}
