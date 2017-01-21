_ = require 'lodash'
uuid = require 'node-uuid'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'

defaultEventAnnouncement = (eventAnnouncement) ->
  unless eventAnnouncement?
    return null

  _.defaults eventAnnouncement, {
    id: uuid.v4()
    creatorId: null
    eventId: null
    title: ''
    body: ''
    time: new Date()
  }

EVENT_ANNOUNCEMENTS_TABLE = 'event_announcements'

class EventAnnouncementModel
  RETHINK_TABLES: [
    {
      name: EVENT_ANNOUNCEMENTS_TABLE
      indexes: [
        {name: GROUP_ID_INDEX}
      ]
    }
  ]

  create: (eventAnnouncement) ->
    eventAnnouncement = defaultEventAnnouncement eventAnnouncement

    r.table EVENT_ANNOUNCEMENTS_TABLE
    .insert eventAnnouncement
    .run()
    .then ->
      eventAnnouncement

  getAllByGroupId: (groupId) ->
    r.table EVENT_ANNOUNCEMENTS_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()

  getAllByIds: (ids) ->
    r.table EVENT_ANNOUNCEMENTS_TABLE
    .getAll ids, {index: GROUP_ID_INDEX}
    .run()

  updateById: (id, diff) ->
    r.table EVENT_ANNOUNCEMENTS_TABLE
    .get id
    .update diff
    .run()

module.exports = new EventAnnouncementModel()
