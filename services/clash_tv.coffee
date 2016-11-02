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

DIR = './resources/grive/clashtv/Screenshots'
SS_OUT_DIR = './resources/clashtv_done'

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
  'lvl l': 1
  'lvl.l': 1
  'lvl 1': 1
  'lvl.1': 1
  'vl.': 1 # some legendaries end up like this (we don't know level, 1 is guess)
  'lvl 2‘': 2
  'lvl.2': 2
  'lvl .2': 2
  'lvll': 2
  'lvl.3': 3
  'lvl3': 3
  'lvvl': 4
  'lvl.4': 4
  'lvl.5': 5
  'lvl5': 5
  'lvl.6': 6
  'lvl.7': 7
  'lvl.8': 8
  'lvl 3': 8
  'lvl.9': 9
  'lvl.5l': 9
  'lvl.10': 10
  'lvl.l0': 10
  'vl.llll': 10
  'lvl.ll1l': 10
  'lvl.ll1': 10
  'lvl.11': 11
  'lvl.ll': 11
  'lvl.l1': 11
  'lvl.12': 12
  'lvl.l2': 12
  'lvl.13': 13
  'lvl.l3': 13


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

LEGENDARY_KEYS = [
  'sparky', 'lava_hound', 'miner', 'the_log', 'princess',
  'ice_wizard', 'graveyard', 'lumberjack', 'inferno_dragon',
  'ice_golem'
]

CARDS_DIR = './resources/clashtv_assets/cards'
cardImages = _.filter fs.readdirSync(CARDS_DIR), (name) ->
  name.indexOf('_small') isnt -1
CARD_IMAGES = _.map cardImages, (file) ->
  {
    path: "./resources/clashtv_assets/cards/#{file}"
    value: file.replace '_small.png', ''
  }

CARD_WIDTH = 50
CARD_HEIGHT = 60
CARD_MARGIN_X = 11
CARD_MARGIN_Y = 12

LEVEL_COLORS =
  legendaryGreen:
    color: [153, 255, 102]
    colors: [[153, 255, 133]]
  legendaryLightGreen:
    color: [153, 255, 219]
    colors: [[153, 255, 219]]
  pink:
    color: [255, 153, 255]
    colors: [[255, 153, 255]]
  legendaryPink:
    color: [255, 186, 223]
    colors: [[255, 186, 223]]
  # legendaryYellow:
  #   color: [255, 255, 153]
  #   colors: [[255, 255, 153]]
  legendaryLightGreen2:
    color: [184, 255, 201]
    colors: [[184, 255, 201]]
  blue:
    color: [153, 204, 255]
    colors: [[153, 204, 255]]
  yellow:
    color: [255, 204, 102]
    colors: [[255, 204, 102]]#, [230, 184, 92]]
RGB_TOLERANCE = 0
COLOR_DETECT_RGB_TOLERANCE = 20
CLASH_TV_PROCESSED_FOLDER_ID = '0B3-QIPiIHJh2WE5TTXhaNVIzeUU'
CLASH_TV_SCREENSHOTS_FOLDER_ID = '0B3-QIPiIHJh2THFSTmJYcDBsdTQ'
cachedImages = []


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


options =
  pageSize: 100
  fields: 'files(id, name)'
  q: "'#{CLASH_TV_SCREENSHOTS_FOLDER_ID}' in parents"


class ClashTvService
  process: ->
    if config.IS_STAGING or config.ENV is config.ENVS.DEV
      console.log 'skipping process'
      return
    Promise.promisify(drive.files.list)(options)
    .then (response) ->
      files = _.map response[0].files, (obj) ->
        _.pick obj, ['id', 'name']

      Promise.each files, ({id, name, downloadUrl}, cur) ->
        ssFileName = name
        fileId = id
        Promise.promisify(drive.files.get) {
          fileId: id
          alt: 'media'
        }, {encoding: null}
        .then ([ssFile]) ->
          image = new Image()
          image.src = ssFile

          # c = new Canvas image.width, image.height
          # ctx = c.getContext '2d'
          # ctx.drawImage image, 0, 0
          # console.log c.toDataURL()

          arenaCanvas = new Canvas 320, 55
          arenaCtx = arenaCanvas.getContext '2d'
          arenaCtx.drawImage image, -128, -160

          score1Canvas = new Canvas 32, 24
          score1Ctx = score1Canvas.getContext '2d'
          score1Ctx.drawImage image, -244, -277

          score2Canvas = new Canvas 32, 24
          score2Ctx = score2Canvas.getContext '2d'
          score2Ctx.drawImage image, -297, -277

          player1Deck = getCardImages image, -38, -316
          player2Deck = getCardImages image, -299, -316

          console.log '====='
          console.log "#{cur} / #{files.length}"

          Promise.all [
            matchImage score1Canvas, SCORE_IMAGES, {maxMismatch: 70}
            matchImage score2Canvas, SCORE_IMAGES, {maxMismatch: 70}
            extractText arenaCanvas, {removeLineBreaks: true}
            Promise.map player1Deck, getCardAndLevel, {concurrency: 1}
            .then (player1Deck) ->
              console.log '--'
              Promise.map player2Deck, getCardAndLevel, {concurrency: 1}
              .then (player2Deck) ->
                {player1Deck, player2Deck}
          ]
          .then ([score1, score2, arena, {player1Deck, player2Deck}]) ->
            # skip if player deck is null (no good match found
            unless player1Deck and player2Deck
              console.log 'missing deck'
              return
            arena = parseInt(TEXT_MATCHES[arena]?.replace 'arena', '')
            if isNaN arena
              console.log 'arena NaN'
              return
            timeArray = ssFileName
                        .replace('Screenshot_', '').replace('.png', '')
                        .split('-')
            timeArray = _.map timeArray, (number, i) ->
              if i is 1
                (Number number) - 1
              else
                Number number

            time = new (Function::bind.apply(Date, [null].concat timeArray))

            player1Cards = _.uniq _.map(player1Deck, 'card')
            player2Cards = _.uniq _.map(player2Deck, 'card')

            getCards player1Cards
            .then (player1Cards) ->
              getCards player2Cards
              .then (player2Cards) -> {player1Cards, player2Cards}
            .then ({player1Cards, player2Cards}) ->
              Promise.all [
                getDeck player1Cards
                getDeck player2Cards
              ]
              .then ([deck1, deck2]) ->
                Match.matchExists {
                  arena, score1, score2, time
                  deck1Id: deck1.id, deck2Id: deck2.id
                }
                .then (isAlreadyProcessed) ->
                  if isAlreadyProcessed
                    return console.log 'dupe'
                  # console.log cards, deck1, deck2
                  p1State = if score1 > score2 \
                            then 'win'
                            else if score2 > score1
                            then 'loss' else 'draw'
                  p2State = if score2 > score1 \
                            then 'win'
                            else if score1 > score2
                            then 'loss' else 'draw'

                  unless IS_TEST_RUN
                    Promise.all [
                      Deck.incrementById deck1.id, p1State
                      Deck.incrementById deck2.id, p2State
                      updateCardCounts player1Cards, p1State
                      .then ->
                        updateCardCounts player2Cards, p2State

                      Match.create {
                        arena: arena
                        deck1Id: deck1.id
                        deck2Id: deck2.id
                        deck1Score: score1
                        deck2Score: score2
                        time: time
                      }
                    ]

          .catch (err) ->
            console.log 'bad image', err
          .then ->
            unless IS_TEST_RUN
              Promise.promisify(drive.files.update) {
                fileId: fileId
                addParents: [CLASH_TV_PROCESSED_FOLDER_ID]
                removeParents: [CLASH_TV_SCREENSHOTS_FOLDER_ID]
                fields: 'id, parents'
              }
        .catch (err) ->
          console.log 'bad image', err
    .then ->
      console.log 'done'

module.exports = new ClashTvService()





















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
