Promise = require 'bluebird'
_ = require 'lodash'

TIME_FOR_INITIAL_GET_MS = 100

class StreamService
  constructor: ->
    @openCursors = {}
    setInterval =>
      console.log 'cursors open: ', _.reduce @openCursors, (count, socket) ->
        count += _.keys(socket).length
        count
      , 0
    , 100000

  exoidDisconnect: (socket) =>
    _.map @openCursors[socket.id], (cursor) ->
      cursor.close()
    delete @openCursors[socket.id]

  stream: ({emit, socket, limit, route, promise, postFn}) =>
    limit ?= 30
    isInitial = true
    promise
    .then (cursor) =>
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
            resolve {initial: items, changes: null}
          if item.type is 'uninitial' or item.type is 'state'
            return false
          postFn item.new_val
          .then (newItem) ->
            if isInitial
              items = items.concat([newItem])
            else
              emit {
                initial: null
                changes: [{oldId: item.old_val?.id, newVal: newItem}]
              }

module.exports = new StreamService()
