_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

PUSH_TOKENS_TABLE = 'push_tokens'
PUSH_TOKENS_TOKEN_INDEX = 'token'
USER_ID_INDEX = 'userId'

defaultToken = (token) ->
  unless token?
    return null

  _.defaults token, {
    id: uuid.v4()
    sourceType: null
    token: null
    isActive: true
    userId: null
    errorCount: 0
  }

class PushToken
  RETHINK_TABLES: [
    {
      name: PUSH_TOKENS_TABLE
      indexes: [
        {name: PUSH_TOKENS_TOKEN_INDEX}
        {name: USER_ID_INDEX}
      ]
    }
  ]

  create: (token) ->
    token = defaultToken token

    r.table PUSH_TOKENS_TABLE
    .insert token
    .run()
    .then ->
      token

  getById: (id) ->
    r.table PUSH_TOKENS_TABLE
    .get id
    .run()
    .then defaultToken

  updateById: (id, diff) ->
    r.table PUSH_TOKENS_TABLE
    .get id
    .update diff
    .run()

  updateByToken: (token, diff) ->
    r.table PUSH_TOKENS_TABLE
    .getAll token, {index: PUSH_TOKENS_TOKEN_INDEX}
    .update diff
    .run()

  deleteById: (id) ->
    r.table PUSH_TOKENS_TABLE
    .get id
    .delete()
    .run()

  getByToken: (token) ->
    r.table PUSH_TOKENS_TABLE
    .getAll token, {index: PUSH_TOKENS_TOKEN_INDEX}
    .nth(0)
    .default(null)
    .run()
    .then defaultToken

  getAllByUserId: (userId) ->
    r.table PUSH_TOKENS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .filter {isActive: true}
    .run()
    .map defaultToken

  sanitizePublic: (token) ->
    _.pick token, [
      'id'
      'userId'
      'token'
      'sourceType'
    ]


module.exports = new PushToken()
