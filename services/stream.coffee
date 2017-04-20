Promise = require 'bluebird'
_ = require 'lodash'

TIME_FOR_INITIAL_GET_MS = 100

class StreamService
  constructor: ->
    @openCursors = {}
    setInterval =>
      cursorsOpen = _.reduce @openCursors, (count, socket) ->
        count += _.keys(socket).length
        count
      , 0
      if cursorsOpen > 10
        console.log 'cursors open: ', cursorsOpen
    , 100000

  exoidDisconnect: (socket) =>
    _.map @openCursors[socket.id], (cursor) ->
      cursor.close()
    delete @openCursors[socket.id]

  stream: ({emit, socket, limit, route, promise, postFn}) =>
    limit ?= 30
    isInitial = true
    start = Date.now()
    promise
    .then (cursor) =>
      console.log 'cc3', Date.now() - start
      start = Date.now()
      # TODO: release cursors when switching to tab/page
      # where obs isn't required?
      if @openCursors[socket.id]?[route]
        @openCursors[socket.id][route].close()

      @openCursors[socket.id] ?= {}
      @openCursors[socket.id][route] = cursor

      items = []
      new Promise (resolve, reject) ->
        cursor.eachAsync (item) ->
          if item.state is 'ready'
            isInitial = false
            resolve items
          if item.type is 'uninitial' or item.type is 'state'
            return false
          postFn item.new_val
          .then (newItem) ->
            if isInitial
              items = _.filter items.concat([newItem])
            else
              # https://github.com/rethinkdb/rethinkdb/issues/6101
              # when using a changefeed with an ordered limit, new inserts
              # are considered changes since it's a change in the list of 30
              # items (even if it's a new item).
              # this is a workaround to determine if it's new
              isInsert = item.old_val?.id isnt newItem?.id
              emit {
                initial: null
                changes: [{
                  oldId: if isInsert then null else item.old_val?.id
                  newVal: newItem
                }]
              }

module.exports = new StreamService()
