Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

CacheService = require './cache'
config = require '../config'

PATH = 'https://api.twitch.tv/kraken'

class TwitchService
  request: (path, {token}) ->
    request "#{PATH}#{path}?client_id=#{config.TWITCH.CLIENT_ID}", {
      json: true
      method: 'GET'
      headers:
        'Authorization': "OAuth #{token}"
    }

  getIsSubscribedToChannelId: (channelName, token) =>
    @request '/user', {token}
    .then (user) =>
      @request "/users/#{user.name}/subscriptions/#{channelName}", {token}
      .then ({created_at}) -> created_at
    .catch ->
      false

module.exports = new TwitchService()
