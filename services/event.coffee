Promise = require 'bluebird'

Event = require '../models/event'
PushNotificationService = require './push_notification'
config = require '../config'

class EventService
  notifyForStart: ->
    Event.getAllStartingNow()
    .then (events) ->
      Promise.each events, (event) ->
        PushNotificationService.sendToEvent event, {
          title: 'Event starting'
          type: PushNotificationService.TYPES.EVENT
          text: "#{event.name} starts in 5 minutes"
          data:
            path: "/event/#{event.id}"
        }

module.exports = new EventService()
