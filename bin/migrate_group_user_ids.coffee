#!/usr/bin/env coffee
_ = require 'lodash'
Promise = require 'bluebird'
GroupUser = require '../models/group_user'
Group = require '../models/group'
r = require '../services/rethinkdb'

return
r.db('radioactive').table('groups')
.filter r.row('hasNewUserIds').default(false).eq(false)
.limit 3000
.run()
.then (groups) ->
  Promise.map groups, (group, i) ->
    Promise.map group.userIds, (userId) ->
      GroupUser.create {userId, groupId: group.id}
    .then ->
      console.log i
      Group.updateById group.id, {hasNewUserIds: true}
  , {concurrency: 200}
.then ->
  console.log 'done'
