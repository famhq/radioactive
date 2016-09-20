_ = require 'lodash'
b = require 'b-assert'
server = require '../../index'
flare = require('flare-gun').express(server.app)

schemas = require '../../schemas'
util = require './util'

describe 'User Routes', ->
  describe 'users.getMe', ->
    it 'returns user', ->
      flare
        .thru util.login()
        .exoid 'users.getMe'
        .expect schemas.user

    describe '400', ->
      it 'fails if missing accessToken', ->
        flare
          .exoid 'users.getMe'
          .expect 401

  describe 'users.updateMe', ->
    it 'updates user', ->
      flare
        .thru util.login()
        .exoid 'users.updateMe', {username: 'changed'}
        .exoid 'users.getMe'
        .expect _.defaults {
          username: 'changed'
        }, schemas.user

    describe '400', ->
      it 'fails if invalid update values', ->
        flare
          .thru util.login()
          .exoid 'users.updateMe', {username: 123}
          .expect 400

      it 'returns 401 if user not authed', ->
        flare
          .exoid 'users.updateMe', {username: 'changed'}
          .expect 401
