# _ = require 'lodash'
#
# uuid = require 'node-uuid'
#
# r = require '../services/rethinkdb'
# config = require '../config'
#
# GAME_KEY_INDEX = 'gameId'
#
# defaultGameRecordType = (gameRecordType) ->
#   unless gameRecordType?
#     return null
#
#   _.defaults gameRecordType, {
#     id: uuid.v4()
#     creatorId: null
#     gameId: null
#     name: null
#     timeScale: null
#     time: new Date()
#   }
#
# GAME_RECORD_TYPES_TABLE = 'game_record_types'
#
# class GameRecordTypeModel
#   RETHINK_TABLES: [
#     {
#       name: GAME_RECORD_TYPES_TABLE
#       indexes: [
#         {
#           name: GAME_KEY_INDEX
#         }
#       ]
#     }
#   ]
#   getById: (id) ->
#     r.table GAME_RECORD_TYPES_TABLE
#     .get id
#     .run()
#     .then defaultGameRecordType
#
#   getAllByGameId: (gameKey) ->
#     if gameKey is 'clash-royale'
#       gameKey = confing.LEGACY_CLASH_ROYALE_ID # FIXME: when migrating to scylla
#
#     r.table GAME_RECORD_TYPES_TABLE
#     .getAll gameKey, {index: GAME_KEY_INDEX}
#     .run()
#
#
#
# module.exports = new GameRecordTypeModel()
