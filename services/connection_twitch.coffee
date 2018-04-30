Promise = require 'bluebird'
_ = require 'lodash'
request = require 'request-promise'

CacheService = require './cache'
Connection = require '../models/connection'
config = require '../config'

LEGACY_PATH = 'https://api.twitch.tv/kraken'
PATH = 'https://api.twitch.tv/helix'

class TwitchService
  get: (path, connection) =>
    {token, refresh_token} = connection
    get = (accessToken) ->
      request "#{LEGACY_PATH}#{path}", {
        json: true
        method: 'GET'
        qs:
          client_id: config.TWITCH.CLIENT_ID
        headers:
          'Authorization': "OAuth #{accessToken}"
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
    @get '/user', connection

  getIsSubscribedToChannelId: (channelName, connection) =>
    @getUserByConnection connection
    .then (user) =>
      @get "/users/#{user.name}/subscriptions/#{channelName}", connection
      .then ({created_at}) -> created_at
    .catch ->
      false

module.exports = new TwitchService()
