#!/usr/bin/env coffee
_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'
Canvas = require 'canvas'
Image = Canvas.Image
resemble = require 'node-resemble-js'
tesseract = require 'node-tesseract'
google = require 'googleapis'
OAuth2 = google.auth.OAuth2
request = require 'request-promise'

config = require '../config'
CanvasToTIFF = require '../lib/canvastotiff.min.js'
Card = require '../models/clash_royale_card'
Match = require '../models/clash_royale_match'
Deck = require '../models/clash_royale_deck'

IS_TEST_RUN = false


oauth2Client = new OAuth2(
  config.GOOGLE.CLIENT_ID
  config.GOOGLE.CLIENT_SECRET
  config.GOOGLE.REDIRECT_URL
)
# scopes = [
#   'https://www.googleapis.com/auth/drive'
# ]
# url = oauth2Client.generateAuthUrl {
#   access_type: 'offline'
#   scope: scopes
# }
# if you need a new refresh_token, get a code (url above), put into var below
# and get token
# code = '4/vJLyVVM20Y45blJbMTv3gM5kP8dMQwxCjHXjJd1xPNk'
# oauth2Client.getToken code, (err, token) ->
#   console.log err, token
oauth2Client.setCredentials {refresh_token: config.GOOGLE.REFRESH_TOKEN}
drive = google.drive {
  version: 'v3',
  auth: oauth2Client
}


class GoogleDriveService
  FOLDERS:
    CLASH_TV_PROCESSED: '0B3-QIPiIHJh2WE5TTXhaNVIzeUU'
    CLASH_TV_SCREENSHOTS: '0B3-QIPiIHJh2THFSTmJYcDBsdTQ'
    CLASH_TV_UNKNOWN: '0B3-QIPiIHJh2OEtqa1hpb0VSZGM'

  getFilesByFolder: (folder) ->
    options =
      pageSize: 100
      fields: 'files(id, name)'
      q: "'#{folder}' in parents"
    console.log 'get by folder', folder
    Promise.promisify(drive.files.list)(options)
    .then (response) ->
      response = response[0] or response
      files = _.map response?.files, (obj) ->
        _.pick obj, ['id', 'name']

  getFileBufferByFileId: (fileId) ->
    Promise.promisify(drive.files.get) {
      fileId: fileId
      alt: 'media'
    }, {encoding: null}

  moveFile: ({fileId, from, to}) ->
    Promise.promisify(drive.files.update) {
      fileId: fileId
      addParents: [to]
      removeParents: [from]
      fields: 'id, parents'
    }

  uploadFile: ({file, folder, name}) ->
    Promise.promisify(drive.files.create) {
      resource: {name, mimeType: 'image/png', parents: [folder]}
      media: {body: file, mimeType: 'image/png'}
    }

module.exports = new GoogleDriveService()





















updateCardCounts = (cards, state) ->
  Promise.map cards, ({id}) ->
    Card.incrementById id, state

getCards = (cards) ->
  Promise.map cards, (card) ->
    Card.getByKey card
    .then (cardObj) ->
      if cardObj
        return cardObj
      else
        unless IS_TEST_RUN
          Card.create {
            key: card
            name: _.startCase card
          }

getDeck = (cards) ->
  cardKeys = Deck.getCardKeys _.map cards, 'key'
  Deck.getByCardKeys cardKeys
  .then (deck) ->
    if deck
      return deck
    else
      if IS_TEST_RUN
        {}
      else
        Deck.getRandomName(cards).then (randomName) ->
          Deck.create {
            cardKeys
            name: randomName
            cardIds: _.map cards, 'id'
          }


extractText = (canvas, {removeLineBreaks, isCharacter, isWord, isLevel} = {}) ->
  new Promise (resolve, reject) ->
    tmpFile = "/tmp/#{Date.now() + Math.random()}"
    new Promise (resolve, reject) ->
      # for whatever reason, tesseract processes ttfs better than pngs...
      CanvasToTIFF.toArrayBuffer [canvas], resolve, {}
    .then (arrayBuffer) ->
      buffer = Buffer.from arrayBuffer
      Promise.promisify(fs.writeFile) tmpFile, buffer
    .then ->
      options =
        c: if isLevel then 'tessedit_char_whitelist=lv.0123456789' else null
        psm: if isCharacter \
            then 10
            else if isWord
            then 7
            else 3
      tesseract.process tmpFile, options, (err, text) ->
        if err
          console.log err
          reject err
        else
          if removeLineBreaks
            text = text.replace /\n/g, ' '
          resolve text.trim()

compareImage = (image1, image2) ->
  new Promise (resolve, reject) ->
    resemble(image1).compareTo(image2.image).ignoreColors().onComplete (data) ->
      resolve {
        value: image2.value
        misMatch: parseFloat(data.misMatchPercentage)
      }

matchImage = (canvas, imagePaths, {maxMismatch} = {}) ->
  mainImage = canvas.toBuffer()

  Promise.map imagePaths, ({path, value}) ->
    key = "#{path}:#{canvas.width}:#{canvas.height}"
    if cachedImages[key]
      cachedImages[key]
    else
      Promise.promisify(fs.readFile) path
      .then (image) ->
        resizedCanvas = new Canvas canvas.width, canvas.height
        resizedCanvasCtx = resizedCanvas.getContext '2d'
        img = new Image()
        img.src = image
        resizedCanvasCtx.drawImage(
          img, 0, 0, img.width, img.height, 0, 0,
          resizedCanvas.width, resizedCanvas.height
        )

        cachedImages[key] = {image: resizedCanvas.toBuffer(), value}
        cachedImages[key]
  .then (images) ->
    Promise.map images, (otherImage) ->
      compareImage mainImage, otherImage
  .then (comparisons) ->
    min = _.minBy(comparisons, 'misMatch')
    if maxMismatch and parseInt(min.misMatch) > maxMismatch
      throw new Error 'max mismatch'
    else
      return min.value

invert = (canvas, ctx) ->
  imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
  data = imageData.data
  i = 0
  while i < data.length
    data[i] = 255 - (data[i])
    data[i + 1] = 255 - (data[i + 1])
    data[i + 2] = 255 - (data[i + 2])
    i += 4
  ctx.putImageData imageData, 0, 0
  canvas

getProminentColors = (data) ->
  i = 0
  colors = _.map LEVEL_COLORS, ({colors}, color) -> {color, count: 0}
  while i < data.length
    r = data[i]
    g = data[i + 1]
    b = data[i + 2]
    index = _.findKey LEVEL_COLORS, ({color}) ->
      Math.abs(r - color[0]) <= COLOR_DETECT_RGB_TOLERANCE and
      Math.abs(g - color[1]) <= COLOR_DETECT_RGB_TOLERANCE and
      Math.abs(b - color[2]) <= COLOR_DETECT_RGB_TOLERANCE
    if index
      _.find(colors, {color: index}).count += 1
    i += 4

  legendaryColorFound = _.find colors, ({color, count}) ->
    color.match(/legendary/) and count > 20
  noOtherColors = _.every colors, ({count}) ->
    count < 7
  isLegendary = noOtherColors or legendaryColorFound

  if isLegendary
    return 'legendary'
  else
    colors = _.orderBy(colors, ['count'], ['desc'])
    return LEVEL_COLORS[colors[0].color].colors

focusText = (canvas, ctx, card) ->
  imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
  data = imageData.data

  colors = getProminentColors data
  isLegendary = colors is 'legendary' or LEGENDARY_KEYS.indexOf(card) isnt -1
  i = 0
  while i < data.length
    r = data[i]
    g = data[i + 1]
    b = data[i + 2]
    if isLegendary
      isLevelText = r is 255 or g is 255 or b is 255
    else
      isLevelText = _.find colors, (rgb) ->
        Math.abs(r - rgb[0]) <= RGB_TOLERANCE and
          Math.abs(g - rgb[1]) <= RGB_TOLERANCE and
          Math.abs(b - rgb[2]) <= RGB_TOLERANCE
    if isLevelText
      data[i] = data[i + 1] = data[i + 2] = 0
    else
      data[i] = data[i + 1] = data[i + 2] = 255
    i += 4
  ctx.putImageData imageData, 0, 0
  # if colors is 'legendary'
  #   console.log canvas.toDataURL()
  canvas

getCardImages = (image, startX, startY) ->
  rows = 2
  columns = 4
  _.flatten(
    _.map _.range(rows), (row) ->
      _.map _.range(columns), (column) ->
        card1Canvas = new Canvas CARD_WIDTH, CARD_HEIGHT
        card1Ctx = card1Canvas.getContext '2d'
        x = startX - (CARD_WIDTH + CARD_MARGIN_X) * column
        y = startY - (CARD_HEIGHT + CARD_MARGIN_Y) * row
        card1Ctx.drawImage image, x, y
        card1Canvas
  )

getCardAndLevel = (canvas) ->
  matchImage canvas, CARD_IMAGES
  .then (card) ->
    unless card
      return null
    levelCanvas = new Canvas 38, 14
    levelCtx = levelCanvas.getContext '2d'
    levelCtx.drawImage canvas, -6, -43
    focusText(levelCanvas, levelCtx, card)
    levelScaledCanvas = new Canvas 360, 140
    levelScaledCtx = levelScaledCanvas.getContext '2d'
    # levelScaledCtx.imageSmoothingEnabled = false
    levelScaledCtx.drawImage(
      levelCanvas, 0, 0, levelCanvas.width, levelCanvas.height
      0, 0, levelScaledCanvas.width, levelScaledCanvas.height
    )
    extractText levelScaledCanvas, {
      # isWord: true, removeLineBreaks: true, isLevel: true
      isLevel: true
    }
    .then (text) ->
      level = TEXT_MATCHES[text]
      unless level
        console.log '****'
        console.log 'MISSING:', card, text
        console.log canvas.toDataURL()
        console.log '****'
      # else
      #   console.log card, level, text

      {card, level}



# give decks names
# r = require '../services/rethinkdb'
# EmbedService = require '../services/embed'
# r.table 'clash_royale_decks'
# .filter r.row('name').default(null).eq(null)
# .limit 500
# .run()
# .map EmbedService.embed [EmbedService.TYPES.CLASH_ROYALE_DECK.CARDS]
# .then (decks) ->
#   Promise.map decks, (deck) ->
#     Deck.getRandomName deck.cards
#     .then (name) ->
#       Deck.updateById deck.id, {name}
#   , {concurrency: 10}
# return

# resize images
# Promise.map CARD_IMAGES, ({path, value}) ->
#   Promise.promisify(fs.readFile) path
#   .then (image) ->
#     resizedCanvas = new Canvas CARD_WIDTH, CARD_HEIGHT
#     resizedCanvasCtx = resizedCanvas.getContext '2d'
#     img = new Image()
#     img.src = image
#     resizedCanvasCtx.drawImage(
#       img, 0, 0, img.width, img.height, 0, 0,
#       resizedCanvas.width, resizedCanvas.height
#     )
#     Promise.promisify(fs.writeFile)(
#       "./resources/clashtv_assets/cards/#{value}_small.png"
#       resizedCanvas.toBuffer()
#     )
# return
