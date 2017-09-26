cassanknex = require 'cassanknex'
cassandra = require 'cassandra-driver'
Promise = require 'bluebird'
_ = require 'lodash'

config = require '../config'

distance = cassandra.types.distance

contactPoints = config.SCYLLA.CONTACT_POINTS

cassanknexInstance = cassanknex
  connection:
    contactPoints: contactPoints
  exec:
    prepare: true
  pooling:
    coreConnectionsPerHost:
      "#{distance.local}": 2
      "#{distance.remote}": 1

ready = new Promise (resolve, reject) ->
  cassanknexInstance.on 'ready', (err, res) ->
    console.log 'cassandra', err, res
    if err
      reject err
    else

      resolve res

cknex = ->
  instance = cassanknexInstance('clash_royale')
  instance.run = (options = {}) -> # skinny arrow on purpose
    self = this
    ready.then ->
      new Promise (resolve, reject) ->
        self.exec options, (err, result) ->
          if err
            reject err
          else
            resolve result
  instance

cknex.getTimeUuid = (time) ->
  if time
    unless time instanceof Date
      time = new Date time
    cassandra.types.TimeUuid.fromDate time
  else
    cassandra.types.TimeUuid.now()

cknex.getTime = (time) ->
  if time
    unless time instanceof Date
      time = new Date time
    time
  else
    new Date()


# batching shouldn't be used much. 50kb limit and:
# https://docs.datastax.com/en/cql/3.1/cql/cql_using/useBatch.html
cknex.batchRun = (queries) ->
  ready.then ->
    new Promise (resolve, reject) ->
      cassanknexInstance('clash_royale').batch queries, (err, result) ->
        if err
          reject err
        else
          resolve result

module.exports = cknex
