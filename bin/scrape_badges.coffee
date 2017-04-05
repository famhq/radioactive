_ = require 'lodash'
Promise = require 'bluebird'
request = require 'request-promise'
fs = require 'fs'

BADGE_COUNT = 180
BASE_URL = 'http://statsroyale.com/images/badges/16000'
_.map _.range(BADGE_COUNT), (index) ->
  padded = _.padStart index, 3, '0'
  url = "#{BASE_URL}#{padded}.png"
  request url, {encoding: 'binary'}
  .then (file) ->
    path = "../design-assets/images/starfire/badges/#{index}.png"
    fs.writeFile path, file, 'binary'
