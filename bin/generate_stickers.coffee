# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
fs = require 'fs'
gm = require 'gm'
Canvas = require 'canvas'
Image = Canvas.Image

setTimeout ->
  Promise.each [
    # ['ph', '../fam-assets/stickers/ph_large.png']
    # ['ph_bruno', '../fam-assets/stickers/bruno_large.png']
    # ['ph_love', '../../Downloads/ph_love.png']
    # ['ph_hmm', '../../Downloads/ph_hmm.png']
    # ['ph_uau', '../../Downloads/ph_uau.png']
    # ['ph_god', '../../Downloads/ph_god.png']
    # ['ph_voa', '../../Downloads/ph_voa.png']
    # ['ph_huum', '../../Downloads/ph_huum.png']
    # ['ph_surpreso', '../../Downloads/ph_surpreso.png']
    # ['ph_feliz', '../../Downloads/ph_feliz.png']
    # ['ph_bora', '../../Downloads/ph_bora.png']
    # ['ph_assustadao', '../../Downloads/ph_assustadao.png']
    # ['ph_aleluia', '../../Downloads/ph_aleluia.png']
    # ['ph_tenso', '../../Downloads/ph_tenso.png']
    # ['bruno', '../fam-assets/stickers/bruno_large.png']
    # ['cr_laughing', '../fam-assets/stickers/cr_laughing_large.png']
    # ['cr_crying', '../fam-assets/stickers/cr_crying_large.png']
    # ['cr_angry', '../fam-assets/stickers/cr_angry_large.png']
    # ['cr_thumbs_up', '../fam-assets/stickers/cr_thumbs_up_large.png']
    # ['cr_blue_king', '../fam-assets/clash_royale/cr_blue_king.png']
    # ['cr_barbarian', '../fam-assets/clash_royale/cr_barbarian.png']
    # # ['cr_epic_chest', '../fam-assets/clash_royale/cr_epic_chest.png']
    # # ['cr_giant_chest', '../fam-assets/clash_royale/cr_giant_chest.png']
    # ['cr_goblin', '../fam-assets/clash_royale/cr_goblin.png']
    # # ['cr_gold_chest', '../fam-assets/clash_royale/cr_gold_chest.png']
    # ['cr_knight', '../fam-assets/clash_royale/cr_knight.png']
    # # ['cr_magical_chest', '../fam-assets/clash_royale/cr_magical_chest.png']
    # ['cr_red_king', '../fam-assets/clash_royale/cr_red_king.png']
    # ['cr_shop_goblin', '../fam-assets/clash_royale/cr_shop_goblin.png']
    # # ['cr_silver_chest', '../fam-assets/clash_royale/cr_silver_chest.png']
    # # ['cr_smc', '../fam-assets/clash_royale/cr_smc.png']
    # ['cr_thumb', '../fam-assets/clash_royale/cr_thumb.png']
    # ['cr_trophy', '../fam-assets/clash_royale/cr_trophy.png']

    # ['cr_en_fam', '../fam-assets/stickers/sf_logo_large.png']
    # ['cr_en_angry', '../fam-assets/stickers/cr_angry_large.png']
    # ['cr_en_crying', '../fam-assets/stickers/cr_crying_large.png']
    # ['cr_en_laughing', '../fam-assets/stickers/cr_laughing_large.png']
    # ['cr_en_shop_goblin', '../fam-assets/clash_royale/cr_shop_goblin.png']
    # ['cr_en_thumbs_up', '../fam-assets/stickers/cr_thumbs_up_large.png']
    # ['cr_en_thumb', '../fam-assets/clash_royale/cr_thumb.png']
    # ['cr_en_trophy', '../fam-assets/clash_royale/cr_trophy.png']
    #
    # ['cr_es_fam', '../fam-assets/stickers/sf_logo_large.png']
    # ['cr_es_angry', '../fam-assets/stickers/cr_angry_large.png']
    # ['cr_es_crying', '../fam-assets/stickers/cr_crying_large.png']
    # ['cr_es_laughing', '../fam-assets/stickers/cr_laughing_large.png']
    # ['cr_es_shop_goblin', '../fam-assets/clash_royale/cr_shop_goblin.png']
    # ['cr_es_thumbs_up', '../fam-assets/stickers/cr_thumbs_up_large.png']
    # ['cr_es_thumb', '../fam-assets/clash_royale/cr_thumb.png']
    # ['cr_es_trophy', '../fam-assets/clash_royale/cr_trophy.png']
    #
    # ['cr_pt_fam', '../fam-assets/stickers/sf_logo_large.png']
    # ['cr_pt_angry', '../fam-assets/stickers/cr_angry_large.png']
    # ['cr_pt_crying', '../fam-assets/stickers/cr_crying_large.png']
    # ['cr_pt_laughing', '../fam-assets/stickers/cr_laughing_large.png']
    # ['cr_pt_shop_goblin', '../fam-assets/clash_royale/cr_shop_goblin.png']
    # ['cr_pt_thumbs_up', '../fam-assets/stickers/cr_thumbs_up_large.png']
    # ['cr_pt_thumb', '../fam-assets/clash_royale/cr_thumb.png']
    # ['cr_pt_trophy', '../fam-assets/clash_royale/cr_trophy.png']

    # ['cr_pl_fam', '../fam-assets/stickers/sf_logo_large.png']
    # ['cr_pl_angry', '../fam-assets/stickers/cr_angry_large.png']
    # ['cr_pl_crying', '../fam-assets/stickers/cr_crying_large.png']
    # ['cr_pl_laughing', '../fam-assets/stickers/cr_laughing_large.png']
    # ['cr_pl_shop_goblin', '../fam-assets/clash_royale/cr_shop_goblin.png']
    # ['cr_pl_thumbs_up', '../fam-assets/stickers/cr_thumbs_up_large.png']
    # ['cr_pl_thumb', '../fam-assets/clash_royale/cr_thumb.png']
    # ['cr_pl_trophy', '../fam-assets/clash_royale/cr_trophy.png']

    # ['nan_gg', '../../Downloads/nan_gg.png']
    # ['nan_get_rekt', '../../Downloads/nan_get_rekt.png']
    # ['nan_gfuel', '../../Downloads/nan_gfuel.png']
    # ['nan_wow', '../../Downloads/nan_wow.png']
    # ['nan', '../../Downloads/nickatnytefish-300.png']
    # ['nan_wow', '../../Downloads/nan_wow.png']

    # ['nan_geet', '../fam_sticker_base/nan_geet.png']
    # ['nan_ice_fish', '../fam_sticker_base/nan_ice_fish.png']
    # ['nan_cheezeit', '../fam_sticker_base/nan_cheezeit.png']
    # ['nan_kiss', '../fam_sticker_base/nan_kiss.png']
    # ['nan_shook', '../fam_sticker_base/nan_shook.png']
    # ['nan_nuts', '../fam_sticker_base/nan_nuts.png']
    # ['nan_nytewitch', '../fam_sticker_base/nan_nytewitch.png']
    # ['nan_ah', '../fam_sticker_base/nan_ah.png']
    # ['nan_terrify', '../fam_sticker_base/nan_terrify.png']
    # ['nan_unicorn', '../fam_sticker_base/nan_unicorn.png']

    # ['nan_snipe1', '../fam_sticker_base/nan/nan_snipe1.png']
    # ['nan_snipe2', '../fam_sticker_base/nan/nan_snipe2.png']
    # ['nan_snipe3', '../fam_sticker_base/nan/nan_snipe3.png']
    # ['nan_snipe4', '../fam_sticker_base/nan/nan_snipe4.png']
    # ['nan_g1', '../fam_sticker_base/nan/nan_g1.png']
    # ['nan_g2', '../fam_sticker_base/nan/nan_g2.png']
    # ['nan_clue', '../fam_sticker_base/nan/nan_clue.png']
    # ['nan_mat', '../fam_sticker_base/nan/nan_mat.png']
    # ['nan_new', '../fam_sticker_base/nan/nan_new.png']
    # ['nan_rip', '../fam_sticker_base/nan/nan_rip.png']



    # ['tq', '../../Downloads/tq.png']
    # ['tq_diegob', '../../Downloads/diegob.png']
    # ['tq_adrian_piedra', '../../Downloads/adrian_piedra.png']
    # ['tq_coltonw83', '../../Downloads/coltonw83.png']

    # ['ninja', '../../Downloads/ninja_k.png']
    # ['ninja_pon', '../../Downloads/ninja_pon.png']
    # ['ninja_hype', '../../Downloads/ninja_hype.png']
    # ['ninja_blast', '../../Downloads/ninja_blast.png']
    # ['ninja_creep', '../../Downloads/ninja_creep.png']
    # ['ninja_aim', '../fam_sticker_base/ninja/ninja_aim.png']
    # ['ninja_amazing', '../fam_sticker_base/ninja/ninja_amazing.png']
    # ['ninja_aww', '../fam_sticker_base/ninja/ninja_aww.png']
    # ['ninja_blast1', '../fam_sticker_base/ninja/ninja_blast1.png']
    # ['ninja_blast2', '../fam_sticker_base/ninja/ninja_blast2.png']
    # ['ninja_blast3', '../fam_sticker_base/ninja/ninja_blast3.png']
    # ['ninja_clap', '../fam_sticker_base/ninja/ninja_clap.png']
    # ['ninja_cry', '../fam_sticker_base/ninja/ninja_cry.png']
    # ['ninja_disco', '../fam_sticker_base/ninja/ninja_disco.png']
    # ['ninja_h', '../fam_sticker_base/ninja/ninja_h.png']
    # ['ninja_iq', '../fam_sticker_base/ninja/ninja_iq.png']
    # ['ninja_pon', '../fam_sticker_base/ninja/ninja_pon.png']
    # ['ninja_s', '../fam_sticker_base/ninja/ninja_s.png']
    # ['ninja_shrug', '../fam_sticker_base/ninja/ninja_shrug.png']
    # ['ninja_wifey', '../fam_sticker_base/ninja/ninja_wifey.png']


    ['tv_ackha', '../fam_sticker_base/tv/tv_ackha.png']
    ['tv_been', '../fam_sticker_base/tv/tv_been.png']
    ['tv_explo', '../fam_sticker_base/tv/tv_explo.png']
    ['tv_disgust', '../fam_sticker_base/tv/tv_disgust.png']
    ['tv_fb', '../fam_sticker_base/tv/tv_fb.png']
    ['tv_geeg', '../fam_sticker_base/tv/tv_geeg.png']
    ['tv_dathwa', '../fam_sticker_base/tv/tv_dathwa.png']

    ['tv_rage', '../fam_sticker_base/tv/tv_rage.png']
    ['tv_sit', '../fam_sticker_base/tv/tv_sit.png']
    ['tv_yeet', '../fam_sticker_base/tv/tv_yeet.png']
    ['tv_yg', '../fam_sticker_base/tv/tv_yg.png']
    ['tv_ppp', '../fam_sticker_base/tv/tv_ppp.png']
    ['tv_booty', '../fam_sticker_base/tv/tv_booty.png']
    ['tv_pppp', '../fam_sticker_base/tv/tv_pppp.png']
    ['tv_gu', '../fam_sticker_base/tv/tv_gu.png']

  ], (args) ->
    generate.apply this, args

generate = (key, path) ->
  dir = key.split('_')?[0]
  Promise.all [
    # level 1 (b&w)
    loadImageFromPath path
    .then blackAndWhite
    # .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_1_large.png", large.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_1_small.png", small.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_1_tiny.png", tiny.toBuffer()

    # level 2 (color)
    loadImageFromPath path
    # .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_2_large.png", large.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_2_small.png", small.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_2_tiny.png", tiny.toBuffer()

    # level 3 (gold)
    loadImageFromPath path
    .then (image) ->
      goldify image, path
    # .then (image) -> stroke image, color
    .then (image) ->
      Promise.all [
        Promise.resolve image
        resize image, 100, 100
        resize image, 30, 30
      ]
    .then ([large, small, tiny]) ->
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_3_large.png", large.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_3_small.png", small.toBuffer()
      fs.writeFileSync "../fam-assets/stickers/#{dir}/#{key}_3_tiny.png", tiny.toBuffer()
  ]
  #
  #
  # getImage().modulate 100, 0, 0
  # .resize 100, 100
  # .write "../fam-assets/stickers/#{key}_1_small.png", _.noop
  #
  # getImage().modulate 100, 0, 0
  # .resize 30, 30
  # .write "../fam-assets/stickers/#{key}_1_tiny.png", _.noop
  #
  # getImage()
  # .resize 300, 300
  # .write "../fam-assets/stickers/#{key}_2_large.png", _.noop
  #
  # getImage().resize 100, 100
  # .write "../fam-assets/stickers/#{key}_2_small.png", _.noop
  #
  # getImage().resize 30, 30
  # .write "../fam-assets/stickers/#{key}_2_tiny.png", _.noop
  #
  # large3Path = "../fam-assets/stickers/#{key}_3_large.png"
  # getImage()
  # .composite '../fam-assets/stickers/sparkle.png'
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
  #       .write "../fam-assets/stickers/#{key}_3_small.png", _.noop
  #
  #       gm(large3Path).resize 30, 30
  #       .write "../fam-assets/stickers/#{key}_3_tiny.png", _.noop

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
  loadImageFromPath '../fam-assets/stickers/sparkle.png'
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
