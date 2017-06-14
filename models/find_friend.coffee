_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
CacheService = require '../services/cache'
config = require '../config'

FIND_FRIENDS_TABLE = 'find_friends'
TIME_LANGUAGE_AND_TROPHIES_INDEX = 'timeLanguageTrophies'
FIFTEEN_MINUTES_SECONDS = 15 * 60

defaultFindFriend = (findFriend) ->
  unless findFriend?
    return null

  _.defaults findFriend, {
    id: uuid.v4()
    userId: null
    playerId: null
    time: new Date()
    language: 'en'
    trophies: 0
  }

class FindFriendModel
  RETHINK_TABLES: [
    {
      name: FIND_FRIENDS_TABLE
      indexes: [
        {name: TIME_LANGUAGE_AND_TROPHIES_INDEX, fn: (row) ->
          [row('time'), row('language'), row('trophies')]}
      ]
    }
  ]

  create: (findFriend) ->
    findFriend = defaultFindFriend findFriend

    r.table FIND_FRIENDS_TABLE
    .insert findFriend
    .run()
    .then ->
      findFriend

  getById: (id) ->
    r.table FIND_FRIENDS_TABLE
    .get id
    .run()
    .then defaultFindFriend
    .catch (err) ->
      console.log 'fail', id
      throw err

  getAll: ({language, trophies} = {}) ->
    trophyBuffer = 4000 # TODO make ~500

    r.table FIND_FRIENDS_TABLE
    .between(
      [
        r.now().sub(FIFTEEN_MINUTES_SECONDS)
        language
        trophies - trophyBuffer
      ]
      [
        r.now()
        language
        trophies + trophyBuffer
      ]
      {index: TIME_LANGUAGE_AND_TROPHIES_INDEX}
    )
    .orderBy {index: r.desc(TIME_LANGUAGE_AND_TROPHIES_INDEX)}
    .limit 30
    .run()
    .map defaultFindFriend

  updateById: (id, diff) ->
    r.table FIND_FRIENDS_TABLE
    .get id
    .update diff
    .run()

  deleteById: (id) ->
    r.table FIND_FRIENDS_TABLE
    .get id
    .delete()
    .run()


module.exports = new FindFriendModel()
