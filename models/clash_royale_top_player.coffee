_ = require 'lodash'
Promise = require 'bluebird'
uuid = require 'node-uuid'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'top_players'
    keyspace: 'clash_royale'
    fields:
      region: 'text'
      rank: 'int'
      playerId: 'text'
    primaryKey:
      partitionKey: ['region']
      clusteringColumns: ['rank']
  }
]

defaultClashRoyaleTopPlayer = (clashRoyaleTopPlayer) ->
  unless clashRoyaleTopPlayer?
    return null

  _.defaults clashRoyaleTopPlayer, {
    region: 'all'
  }

class ClashRoyaleTopPlayerModel
  SCYLLA_TABLES: tables

  getAll: ->
    cknex('clash_royale').select '*'
    .from 'top_players'
    .where 'region', '=', 'all'
    .run()
    .map defaultClashRoyaleTopPlayer

  upsert: (topPlayer) ->
    topPlayer = defaultClashRoyaleTopPlayer topPlayer
    cknex('clash_royale').update 'top_players'
    .set _.omit topPlayer, [
      'region', 'rank'
    ]
    .where 'region', '=', topPlayer.region
    .andWhere 'rank', '=', topPlayer.rank
    .run()

module.exports = new ClashRoyaleTopPlayerModel()
