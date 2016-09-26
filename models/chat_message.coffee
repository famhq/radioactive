_ = require 'lodash'
Promise = require 'bluebird'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'
User = require './user'
CacheService = require '../services/cache'

defaultChatMessage = (chatMessage) ->
  unless chatMessage?
    return null

  _.defaults chatMessage, {
    id: uuid.v4()
    userId: null
    time: new Date()
    body: ''
    toId: null
  }

CHAT_MESSAGES_TABLE = 'chat_messages'
TIME_INDEX = 'time'
USER_ID_INDEX = 'userId'
TO_ID_INDEX = 'toId'
MAX_MESSAGES = 30
FIVE_MINUTES_SECONDS = 60 * 5
TWELVE_HOURS_SECONDS = 3600 * 12
SEVEN_DAYS_SECONDS = 3600 * 24 * 7
TWO_SECONDS = 2

class ChatMessageModel
  RETHINK_TABLES: [
    {
      name: CHAT_MESSAGES_TABLE
      indexes: [
        {
          name: TIME_INDEX
        }
        {
          name: USER_ID_INDEX
        }
        {
          name: TO_ID_INDEX
        }
      ]
    }
  ]

  create: (chatMessage) ->
    chatMessage = defaultChatMessage chatMessage

    r.table CHAT_MESSAGES_TABLE
    .insert chatMessage
    .run()
    .then ->
      chatMessage

  getAll: ->
    r.table CHAT_MESSAGES_TABLE
    .orderBy {index: r.desc(TIME_INDEX)}
    .limit MAX_MESSAGES
    .filter r.row('toId').default(null).eq(null)
    .run()
    .map defaultChatMessage

  getAllByUserIds: ({user1, user2}) ->
    r.union(
      r.table CHAT_MESSAGES_TABLE
      .getAll user1, {index: USER_ID_INDEX}
      .filter {toId: user2}
      .orderBy r.desc(TIME_INDEX)
      .limit MAX_MESSAGES

      r.table CHAT_MESSAGES_TABLE
      .getAll user2, {index: USER_ID_INDEX}
      .filter {toId: user1}
      .orderBy r.desc(TIME_INDEX)
      .limit MAX_MESSAGES
    )
    .distinct()
    .orderBy r.desc(TIME_INDEX)
    .limit MAX_MESSAGES
    .run()
    .map defaultChatMessage

  getById: (id) ->
    r.table CHAT_MESSAGES_TABLE
    .get id
    .run()
    .then defaultChatMessage

  deleteOld: ->
    Promise.all [
      r.table CHAT_MESSAGES_TABLE
      .between 0, r.now().sub(TWELVE_HOURS_SECONDS), {index: TIME_INDEX}
      .filter(
        r.row('toId').default(null).eq(null)
      )
      .delete()

      r.table CHAT_MESSAGES_TABLE
      .between 0, r.now().sub(SEVEN_DAYS_SECONDS), {index: TIME_INDEX}
      .delete()
    ]


module.exports = new ChatMessageModel()
