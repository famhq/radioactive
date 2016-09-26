#!/usr/bin/env coffee
_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'
Canvas = require 'canvas'
Image = Canvas.Image
resemble = require 'node-resemble-js'
textract = require 'textract'
tesseract = require 'node-tesseract'

FOLDER = './resources/grive/clashtv/Screenshots'

# grive -a --ignore '^(?!clashtv($|/))'

TEXT_MATCHES =
  'Goblin SfadiuM Anemia l': 'arena1'
  'Bone Pif Anemia Z': 'arena2'
  'Banbaniau Bowl Anemia 3': 'arena3'
  'RE.I(.I(.A\'s Plavnnuse Anemia 4': 'arena4'
  'Spell Vallev Anemia 5': 'arena5'
  'Builden\'s WORKSHOP Anemia E': 'arena6'
  'anal Aneua Anemia 7': 'arena7'
  'anzeu Peak Anemia B': 'arena8'
  'Legendanv Aneua Anemia B': 'arena9'
  'lvl.l': 1
  'IvLI': 1
  'lle': 2
  '|vl.2': 2
  'm:': 3
  'Ma': 3

SCORE_IMAGES = [
  {
    path: './resources/clashtv_assets/scores/score_0.png'
    value: 0
  }
  {
    path: './resources/clashtv_assets/scores/score_1.png'
    value: 1
  }
  {
    path: './resources/clashtv_assets/scores/score_2.png'
    value: 2
  }
  {
    path: './resources/clashtv_assets/scores/score_3.png'
    value: 3
  }
]

CARDS_FOLDER = './resources/clashtv_assets/cards'
cardImages = _.filter fs.readdirSync(CARDS_FOLDER), (name) ->
  name.indexOf('_small') isnt -1
CARD_IMAGES = _.map cardImages, (file) ->
  {
    path: "./resources/clashtv_assets/cards/#{file}"
    value: file.replace '_small.png', ''
  }

CARD_WIDTH = 100
CARD_HEIGHT = 120
CARD_MARGIN_X = 22
CARD_MARGIN_Y = 24

LEVEL_COLORS = [
  [149, 201, 251] # blue
  [255, 153, 255] # pink
  [255, 204, 102] # yellow
  [230, 184, 92] # yellow
  [173, 255, 133] # green
]

cachedImages = []


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

extractText = (canvas, {removeLineBreaks, isCharacter, isWord} = {}) ->
  new Promise (resolve, reject) ->
    tmpFile = "/tmp/#{Date.now() + Math.random()}"
    Promise.promisify(fs.writeFile) tmpFile, canvas.toBuffer()
    .then ->
      options =
        psm: if isCharacter \
            then 10
            else if isWord
            then 7
            else 3
      console.log options
      tesseract.process tmpFile, options, (err, text) ->
        if err
          reject error
        else
          if removeLineBreaks
            text = text.replace /\n/g, ' '
          resolve text.trim()

compareImage = (image1, image2) ->
  new Promise (resolve, reject) ->
    resemble(image1).compareTo(image2.image).onComplete (data) ->
      resolve {
        value: image2.value
        misMatch: parseFloat(data.misMatchPercentage)
      }

matchImage = (canvas, imagePaths) ->
  mainImage = canvas.toBuffer()
  Promise.map imagePaths, ({path, value}) ->
    if cachedImages[path]
      cachedImages[path]
    else
      Promise.promisify(fs.readFile) path
      .then (image) ->
        cachedImages[path] = {image, value}
        cachedImages[path]
  .then (images) ->
    Promise.map images, (otherImage) ->
      compareImage mainImage, otherImage
  .then (comparisons) ->
    _.minBy(comparisons, 'misMatch')?.value

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

focusText = (canvas, ctx) ->
  imageData = ctx.getImageData(0, 0, canvas.width, canvas.height)
  data = imageData.data
  i = 0
  while i < data.length
    r = data[i]
    g = data[i + 1]
    b = data[i + 2]
    isLevelText = _.find LEVEL_COLORS, (rgb) ->
      Math.abs(r - rgb[0]) < 15 and
      Math.abs(g - rgb[1]) < 15 and
      Math.abs(b - rgb[2]) < 15
    if isLevelText
      data[i] = data[i + 1] = data[i + 2] = 0
    else
      data[i] = data[i + 1] = data[i + 2] = 255
    i += 4
  ctx.putImageData imageData, 0, 0
  console.log canvas.toDataURL()
  canvas

getDeck = (image, startX, startY) ->
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

getCardAndLevel =  (canvas) ->
  matchImage canvas, CARD_IMAGES
  .then (card) ->
    levelCanvas = new Canvas 80, 40
    levelCtx = levelCanvas.getContext '2d'
    levelCtx.drawImage canvas, -14, -80
    extractText focusText(levelCanvas, levelCtx), {
      isWord: true, removeLineBreaks: true
    }
    .then (level) ->
      # console.log levelCanvas.toDataURL()

      {card, level}

Promise.each _.take([fs.readdirSync(FOLDER)[0]], 1), (ssFileName) ->
  ssFilePath = './resources/grive/clashtv/Screenshots/' + ssFileName
  Promise.promisify(fs.readFile) ssFilePath
  .then (ssFile) ->
    image = new Image()
    image.src = ssFile

    arenaCanvas = new Canvas 640, 110
    arenaCtx = arenaCanvas.getContext '2d'
    arenaCtx.drawImage image, -256, -320

    score1Canvas = new Canvas 64, 48
    score1Ctx = score1Canvas.getContext '2d'
    score1Ctx.drawImage image, -488, -554

    score2Canvas = new Canvas 64, 48
    score2Ctx = score2Canvas.getContext '2d'
    score2Ctx.drawImage image, -297, -554

    player1Deck = getDeck image, -76, -632
    player2Deck = getDeck image, -598, -632

    Promise.all [
      extractText arenaCanvas, {removeLineBreaks: true}
      matchImage score1Canvas, SCORE_IMAGES
      matchImage score2Canvas, SCORE_IMAGES
      Promise.map player1Deck, getCardAndLevel
      Promise.map player2Deck, getCardAndLevel
    ]
    .then ([arena, score1, score2, player1Deck, player2Deck]) ->
      arena = TEXT_MATCHES[arena]
      console.log arena, score1, score2, player1Deck, player2Deck



    # resemble(folder).compareTo
    # fs.writeFile "./resources/generated_backs/card_#{number}.svg", svg, 'utf8'
