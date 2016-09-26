_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'
config = require '../config'

JOIN_REQUESTS_TABLE = 'join_requests'
USER_ID_INDEX = 'userId'

defaultJoinRequest = (joinRequest) ->
  unless joinRequest?
    return null

  _.defaults joinRequest, {
    id: uuid.v4()
    gameUsername: null
    gameClan: null
    email: null
    time: new Date()
  }

class JoinRequest
  RETHINK_TABLES: [
    {
      name: JOIN_REQUESTS_TABLE
      indexes: [
        {
          name: USER_ID_INDEX
        }
      ]
    }
  ]

  create: (joinRequest) ->
    joinRequest = defaultJoinRequest joinRequest

    r.table JOIN_REQUESTS_TABLE
    .insert joinRequest
    .run()


module.exports = new JoinRequest()
