server = require '../../index'
flare = require('flare-gun').express(server.app)

describe 'Health Check Routes', ->
  describe 'GET /healthcheck', ->
    it 'returns healthy', ->
      flare
        .get '/healthcheck'
        .expect 200,
          rethinkdb: true
          healthy: true

  describe 'GET /ping', ->
    it 'pongs', ->
      flare
        .get '/ping'
        .expect 200, 'pong'

  describe 'POST /log', ->
    it 'logs', ->
      flare
        .post '/log',
          event: 'client_error'
          message: 'test'
        .expect 204

    describe '400', ->
      it 'fails to log non client_error events', ->
        flare
          .post '/log',
            event: 'xxx'
            message: 'xxx'
          .expect 400
