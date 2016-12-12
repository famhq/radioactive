_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

NOTIFICATIONS_TABLE = 'notifications'
USER_ID_INDEX = 'userId'
TIME_INDEX = 'time'

defaultNotification = (notification) ->
  unless notification?
    return null

  _.defaults notification, {
    id: uuid.v4()
    title: null
    text: null
    data: null
    type: null
    userId: null
    fromId: null
    isRead: false
    time: new Date()
  }

class Notification
  RETHINK_TABLES: [
    {
      name: NOTIFICATIONS_TABLE
      indexes: [
        {
          name: USER_ID_INDEX
        }
        {
          name: TIME_INDEX
        }
      ]
    }
  ]

  create: (notification) ->
    notification = defaultNotification notification

    r.table NOTIFICATIONS_TABLE
    .insert notification
    .run()

  getAllByUserId: (userId, {limit}) ->
    r.table NOTIFICATIONS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .orderBy r.desc TIME_INDEX
    .limit limit
    .run()
    .map defaultNotification

  markReadByUserId: (userId) ->
    r.table NOTIFICATIONS_TABLE
    .getAll userId, {index: USER_ID_INDEX}
    .filter isRead: false
    .update isRead: true
    .run()

  sanitizePrivate: (notification) ->
    _.pick notification, [
      'id'
      'title'
      'text'
      'data'
      'type'
      'userId'
      'isRead'
      'time'
    ]


module.exports = new Notification()
