_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
fs = require 'fs'
gm = require 'gm'

Card = require '../models/clash_royale_card'

names =
  arrows: 'order_volley'
  balloon: 'chr_balloon'
  cannon: 'chaos_cannon'
  clone: 'copy'
  elite_barbarians: 'angry_barbarian'
  inferno_tower: 'building_inferno'
  ice_spirit: 'snow_spirits'
  elixir_collector: 'building_elixir_collector'
  furnace: 'firespirit_hut'
  golem: 'chr_golem'
  fireball: 'fire_fireball'
  dart_goblin: 'blowdart_goblin'
  goblin_hut: 'fire_furnace'
  guards: 'skeleton_warriors'
  lumberjack: 'rage_barbarian'
  minions: 'minion'
  mortar: 'building_mortar'
  night_witch: 'dark_witch'
  sparky: 'zapMachine'
  skeleton_army: 'skeleton_horde'
  tesla: 'building_tesla'
  spear_goblins: 'goblin_archer'
  x_bow: 'building_xbow'
  witch: 'chr_witch'


Card.getAll()
.map (card) ->
  name = names[card.key] or card.key
  url = "http://statsroyale.com/images/cards/full/#{name}.png"
  # console.log 'try', card.key
  request url, {encoding: 'binary'}
  .catch ->
    console.log 'fail', card.key
  .then (file) ->
    # console.log card.key
    path = "../design-assets/images/starfire/cards/#{card.key}.png"
    fs.writeFileSync path, file, 'binary'

    image = gm path
    image = image.resize 125, 150
    image.toBuffer 'png', (err, buffer) ->
      path = "../design-assets/images/starfire/cards/#{card.key}_small.png"
      fs.writeFile path, buffer, 'binary'
.then ->
  console.log 'done'
