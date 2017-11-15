# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
fs = require 'fs'
gm = require 'gm'
Canvas = require 'canvas'
Image = Canvas.Image

COLORS =
  common: 'rgba(0, 0, 255, 1)'

# key = 'sf_logo'
# path = '../starfire-assets/stickers/sf_logo_large.png'
# color = COLORS.common
# getImage = ->
#   gm path

setTimeout ->
  Promise.each [
    ['ph', '../starfire-assets/stickers/ph_large.png', COLORS.common]
    ['ph_bruno', '../starfire-assets/stickers/bruno_large.png', COLORS.common]
    ['ph_love', '../../Downloads/ph_love.png', COLORS.rare]
    ['ph_hmm', '../../Downloads/ph_hmm.png', COLORS.rare]
    ['ph_uau', '../../Downloads/ph_uau.png', COLORS.rare]
    ['ph_god', '../../Downloads/ph_god.png', COLORS.rare]
    ['ph_voa', '../../Downloads/ph_voa.png', COLORS.rare]
    ['ph_huum', '../../Downloads/ph_huum.png', COLORS.rare]
    ['ph_surpreso', '../../Downloads/ph_surpreso.png', COLORS.rare]
    ['ph_feliz', '../../Downloads/ph_feliz.png', COLORS.rare]
    ['ph_bora', '../../Downloads/ph_bora.png', COLORS.rare]
    ['ph_assustadao', '../../Downloads/ph_assustadao.png', COLORS.rare]
    ['ph_aleluia', '../../Downloads/ph_aleluia.png', COLORS.rare]
    ['ph_tenso', '../../Downloads/ph_tenso.png', COLORS.rare]
    # ['bruno', '../starfire-assets/stickers/bruno_large.png', COLORS.common]
    # ['cr_laughing', '../starfire-assets/stickers/cr_laughing_large.png', COLORS.common]
    # ['cr_crying', '../starfire-assets/stickers/cr_crying_large.png', COLORS.common]
    # ['cr_angry', '../starfire-assets/stickers/cr_angry_large.png', COLORS.common]
    # ['cr_thumbs_up', '../starfire-assets/stickers/cr_thumbs_up_large.png', COLORS.common]
    # ['cr_blue_king', '../starfire-assets/clash_royale/cr_blue_king.png', COLORS.common]
    # ['cr_barbarian', '../starfire-assets/clash_royale/cr_barbarian.png', COLORS.epic]
    # # ['cr_epic_chest', '../starfire-assets/clash_royale/cr_epic_chest.png', COLORS.epic]
    # # ['cr_giant_chest', '../starfire-assets/clash_royale/cr_giant_chest.png', COLORS.rare]
    # ['cr_goblin', '../starfire-assets/clash_royale/cr_goblin.png', COLORS.rare]
    # # ['cr_gold_chest', '../starfire-assets/clash_royale/cr_gold_chest.png', COLORS.common]
    # ['cr_knight', '../starfire-assets/clash_royale/cr_knight.png', COLORS.rare]
    # # ['cr_magical_chest', '../starfire-assets/clash_royale/cr_magical_chest.png', COLORS.rare]
    # ['cr_red_king', '../starfire-assets/clash_royale/cr_red_king.png', COLORS.common]
    # ['cr_shop_goblin', '../starfire-assets/clash_royale/cr_shop_goblin.png', COLORS.common]
    # # ['cr_silver_chest', '../starfire-assets/clash_royale/cr_silver_chest.png', COLORS.common]
    # # ['cr_smc', '../starfire-assets/clash_royale/cr_smc.png', COLORS.legendary]
    # ['cr_thumb', '../starfire-assets/clash_royale/cr_thumb.png', COLORS.common]
    # ['cr_trophy', '../starfire-assets/clash_royale/cr_trophy.png', COLORS.common]
  ], (args) ->
    generate.apply this, args

generate = (key, path, color) ->
  Promise.all [
    # level 1 (b&w)
    loadImageFromPath path
    .then blackAndWhite
    .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../starfire-assets/stickers/#{key}_1_large.png", large.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_1_small.png", small.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_1_tiny.png", tiny.toBuffer()

    # level 2 (color)
    loadImageFromPath path
    .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../starfire-assets/stickers/#{key}_2_large.png", large.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_2_small.png", small.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_2_tiny.png", tiny.toBuffer()

    # level 3 (gold)
    loadImageFromPath path
    .then (image) ->
      goldify image, path
    .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../starfire-assets/stickers/#{key}_3_large.png", large.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_3_small.png", small.toBuffer()
      fs.writeFileSync "../starfire-assets/stickers/#{key}_3_tiny.png", tiny.toBuffer()
  ]
  #
  #
  # getImage().modulate 100, 0, 0
  # .resize 100, 100
  # .write "../starfire-assets/stickers/#{key}_1_small.png", _.noop
  #
  # getImage().modulate 100, 0, 0
  # .resize 30, 30
  # .write "../starfire-assets/stickers/#{key}_1_tiny.png", _.noop
  #
  # getImage()
  # .resize 300, 300
  # .write "../starfire-assets/stickers/#{key}_2_large.png", _.noop
  #
  # getImage().resize 100, 100
  # .write "../starfire-assets/stickers/#{key}_2_small.png", _.noop
  #
  # getImage().resize 30, 30
  # .write "../starfire-assets/stickers/#{key}_2_tiny.png", _.noop
  #
  # large3Path = "../starfire-assets/stickers/#{key}_3_large.png"
  # getImage()
  # .composite '../starfire-assets/stickers/sparkle.png'
  # .write large3Path, (err) ->
  #   console.log err
  #   goldImage = gm large3Path
  #   goldImage
  #   .resize 300, 300
  #   # .modulate 130, 0, 50
  #   # .colorize 7, 21, 100
  #   .write large3Path, ->
  #     maskImage large3Path, path
  #     .then ->
  #       gm(large3Path).resize 100, 100
  #       .write "../starfire-assets/stickers/#{key}_3_small.png", _.noop
  #
  #       gm(large3Path).resize 30, 30
  #       .write "../starfire-assets/stickers/#{key}_3_tiny.png", _.noop

loadImageFromPath = (path) ->
  console.log 'load from path', path
  Promise.promisify(fs.readFile) path
  .then (imageSrc) ->
    new Promise (resolve, reject) ->
      image = new Image()

      image.onload = ->
        canvas = new Canvas image.width, image.height
        ctx = canvas.getContext '2d'
        ctx.drawImage image, 0, 0
        canvas
        resolve canvas

      image.onerror = (err) ->
        console.log err

      image.src = imageSrc


blackAndWhite = (image) ->
  canvas = new Canvas image.width, image.height
  ctx = canvas.getContext '2d'

  # this is ideal implementation, but doesn't seem to work in node
  # ctx.globalCompositeOperation = 'luminosity'

  ctx.drawImage image, 0, 0
  # https://stackoverflow.com/a/35180284
  imgPixels = ctx.getImageData 0, 0, canvas.width, canvas.height
  y = 0
  while y < imgPixels.height
    x = 0
    while x < imgPixels.width
      i = y * 4 * imgPixels.width + x * 4
      avg = (imgPixels.data[i] + imgPixels.data[i + 1] +
              imgPixels.data[i + 2]) / 3
      imgPixels.data[i] = avg
      imgPixels.data[i + 1] = avg
      imgPixels.data[i + 2] = avg
      x += 1
    y += 1
  ctx.putImageData imgPixels, 0, 0, 0, 0, imgPixels.width, imgPixels.height
  Promise.resolve canvas

goldify = (image, path) ->
  canvas = new Canvas image.width, image.height
  ctx = canvas.getContext '2d'
  ctx.drawImage image, 0, 0
  imgPixels = ctx.getImageData 0, 0, canvas.width, canvas.height
  y = 0
  while y < imgPixels.height
    x = 0
    while x < imgPixels.width
      i = y * 4 * imgPixels.width + x * 4
      avg = (imgPixels.data[i] + imgPixels.data[i + 1] +
              imgPixels.data[i + 2]) / 3
      imgPixels.data[i] = avg + 60
      imgPixels.data[i + 1] = avg + 20
      imgPixels.data[i + 2] = avg - 150
      x += 1
    y += 1
  ctx.putImageData imgPixels, 0, 0, 0, 0, imgPixels.width, imgPixels.height
  loadImageFromPath '../starfire-assets/stickers/sparkle.png'
  .then (sparkleImage) ->
    ctx.drawImage sparkleImage, 0, 0
    canvas
    mask canvas, path

resize = (image, width, height) ->
  canvas = new Canvas width, height
  ctx = canvas.getContext '2d'
  ctx.drawImage(
    image, 0, 0, image.width, image.height, 0, 0, canvas.width, canvas.height
  )
  Promise.resolve canvas

mask = (image, maskPath) ->
  canvas = new Canvas image.width, image.height
  ctx = canvas.getContext '2d'
  loadImageFromPath maskPath
  .then (mask) ->
    maskCanvas = new Canvas()
    maskCanvas.width = canvas.width
    maskCanvas.height = canvas.height
    maskCtx = maskCanvas.getContext '2d'
    maskCtx.drawImage mask, 0, 0, mask.width, mask.height,
                  0, 0, canvas.width, canvas.height

    ctx.drawImage mask, 0, 0, mask.width, mask.height,
                  0, 0, canvas.width, canvas.height
    ctx.globalCompositeOperation = 'source-in'
    ctx.drawImage image, 0, 0, image.width, image.height,
        0, 0, canvas.width, (image.width / image.height) * canvas.height

    canvas

stroke = (image, color) ->
  return image # disable for now
  canvas = new Canvas image.width, image.height
  thickness = 6
  x = 0#thickness
  y = thickness #* 2
  # give space for stroke
  # resize image, image.width - thickness * 2, image.height - thickness * 2
  resize image, image.width - thickness, image.height - thickness
  .then (image) ->
    ctx = canvas.getContext '2d'
    # https://stackoverflow.com/a/28416298
    dArr = [
      # -1, -1,
      0, -1,
      # 1, -1,
      # -1, 0,
      # 1, 0,
      # -1, 1,
      0, 1,
      # 1, 1
    ]
    i = 0
    while i < dArr.length
      ctx.drawImage image, x + dArr[i] * thickness, y + dArr[i + 1] * thickness
      i += 2

    ctx.globalCompositeOperation = 'source-in'
    ctx.fillStyle = color
    ctx.fillRect 0, 0, canvas.width, canvas.height

    ctx.globalCompositeOperation = 'source-over'
    ctx.drawImage image, 0, 0#thickness, thickness
    canvas

# gm mask doesn't seem to work correctly
# maskImage = (compositePath, maskPath) ->
#   loadImageFromPath compositePath
#   .then (image) ->
#     canvas = new Canvas 300, 300
#     ctx = canvas.getContext '2d'
#     loadImageFromPath maskPath
#     .then (mask) ->
#       maskCanvas = new Canvas()
#       maskCanvas.width = canvas.width
#       maskCanvas.height = canvas.height
#       maskCtx = maskCanvas.getContext '2d'
#       maskCtx.drawImage mask, 0, 0, mask.width, mask.height,
#                     0, 0, canvas.width, canvas.height
#
#       ctx.drawImage mask, 0, 0, mask.width, mask.height,
#                     0, 0, canvas.width, canvas.height
#       ctx.globalCompositeOperation = 'source-in'
#       ctx.drawImage image, 0, 0, image.width, image.height,
#           0, 0, canvas.width, (image.width / image.height) * canvas.height
#
#       canvas
# # coffeelint: disable=max_line_length,cyclomatic_complexity
