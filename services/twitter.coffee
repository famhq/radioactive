Promise = require 'bluebird'
Twit = require 'twit'

config = require '../config'

class TwitterService
  constructor: ->
    @T = new Twit({
      consumer_key: config.TWITTER.CONSUMER_KEY
      consumer_secret: config.TWITTER.CONSUMER_SECRET
      access_token: config.TWITTER.ACCESS_TOKEN
      access_token_secret: config.TWITTER.ACCESS_TOKEN_SECRET
      timeout_ms: 60 * 1000
    })

  get: ->
    @T.get arguments...

  post: ->
    @T.post arguments...



module.exports = new TwitterService()
