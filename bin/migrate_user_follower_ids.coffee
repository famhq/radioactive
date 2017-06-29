#!/usr/bin/env coffee
_ = require 'lodash'
Promise = require 'bluebird'
UserFollower = require '../models/group_user'
UserData = require '../models/user_data'
r = require '../services/rethinkdb'


r.db('radioactive').table('user_data')
.filter r.row('hasNewUserFollowerIds').default(false).eq(false)
.withFields ['followingIds', 'userId']
.limit 20000
.run()
.then (userData) ->
  Promise.map userData, (ud, i) ->
    Promise.map ud.followingIds, (userId) ->
      UserFollower.create {followingId: userId, userId: ud.userId}
    .then ->
      console.log i
      UserData.upsertByUserId ud.userId, {hasNewUserFollowerIds: true}
  , {concurrency: 200}
.then ->
  console.log 'done'
