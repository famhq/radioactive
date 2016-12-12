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
    items = []
    isResolved = false
    promise
    .then (cursor) =>
      # TODO: release cursors when switching to tab where obs isn't required?
      if @openCursors[socket.id]?[route]
        # console.log 'existing cursor, closing'
        @openCursors[socket.id][route].close()

      @openCursors[socket.id] ?= {}
      @openCursors[socket.id][route] = cursor

      new Promise (resolve, reject) ->
        setTimeout ->
          isResolved = true
          resolve items
        , TIME_FOR_INITIAL_GET_MS
        cursor.eachAsync (item) ->
          postFn item.new_val
          .then (item) ->
            if item
              items = _.take items.concat([item]), limit
              if isResolved
                emit items
            null

module.exports = new StreamService()
