Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

CacheService = require './cache'
Connection = require '../models/connection'
config = require '../config'

LEGACY_PATH = 'https://api.twitch.tv/kraken'
PATH = 'https://api.twitch.tv/helix'

class TwitchService
  get: (path, connection, {isLegacy, qs} = {}) =>
    {token, refresh_token} = connection

    if isLegacy
      get = (accessToken) ->
        request "#{LEGACY_PATH}#{path}", {
          json: true
          method: 'GET'
          qs:
            _.defaults {client_id: config.TWITCH.CLIENT_ID}, qs
          headers:
            'Authorization': "OAuth #{accessToken}"
        }
    else
      get = (accessToken) ->
        request "#{PATH}#{path}", {
          json: true
          method: 'GET'
          qs:
            _.defaults {client_id: config.TWITCH.CLIENT_ID}, qs
          headers:
            'Client-ID': 'hrucpw1vzi5ocggczj1mmcdh8hxq7m'
            'Authorization': if accessToken \
                             then "OAuth #{accessToken}"
                             else "Bearer #{config.TWITCH.CLIENT_ID}"
        }

    get token
    .catch (err) =>
      if err.statusCode is 401
        @refreshToken connection
        .then (token) ->
          get token
      else
        throw err

  getInfoFromCode: (code) ->
    request "#{LEGACY_PATH}/oauth2/token", {
      json: true
      method: 'POST'
      qs:
        client_id: config.TWITCH.CLIENT_ID
        client_secret: config.TWITCH.CLIENT_SECRET
        grant_type: 'authorization_code'
        redirect_uri: if config.ENV is config.ENVS.DEV
          'http://192.168.0.109.xip.io:50340/connectionLanding/twitch'
        else
          'https://openfam.com/connectionLanding/twitch'
        code: code
    }

  refreshToken: (connection) ->
    request "#{LEGACY_PATH}/oauth2/token", {
      json: true
      method: 'POST'
      qs:
        client_id: config.TWITCH.CLIENT_ID
        client_secret: config.TWITCH.CLIENT_SECRET
        grant_type: 'refresh_token'
        refresh_token: connection.data.refreshToken
    }
    .then (response) ->
      Connection.upsert _.defaultsDeep {
        token: response.access_token
        data:
          refreshToken: response.refresh_token
      }, connection
      .then ->
        response.access_token


  getUserByConnection: (connection) =>
    @get '/user', connection, {isLegacy: true}

  getIsFollowingChannelId: (channelId, connection) =>
    @get(
      '/users/follows'
      connection
      , {
        qs: {from_id: connection.sourceId, to_id: channelId}
      }
    )

  getIsSubscribedToChannelName: (channelName, connection) =>
    @getUserByConnection connection
    .then (user) =>
      @get(
        "/users/#{user.name}/subscriptions/#{channelName}"
        connection
        {isLegacy: true}
      )
      .then ({created_at}) -> created_at
    .catch ->
      false

module.exports = new TwitchService()
