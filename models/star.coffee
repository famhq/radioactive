_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'
USERNAME_INDEX = 'username'

defaultStar = (star) ->
  unless star?
    return null

  _.defaults star, {
    id: uuid.v4()
    userId: null
    username: null
    groupId: null
  }

STARS_TABLE = 'stars'

class StarModel
  RETHINK_TABLES: [
    {
      name: STARS_TABLE
      indexes: [
        {name: USERNAME_INDEX}
        {name: GROUP_ID_INDEX}
      ]
    }
  ]

  getByUsername: (username) ->
    r.table STARS_TABLE
    .getAll username, {index: USERNAME_INDEX}
    .nth 0
    .default null
    .run()
    .then defaultStar


module.exports = new StarModel()
