_ = require 'lodash'

uuid = require 'node-uuid'

r = require '../services/rethinkdb'

GROUP_ID_INDEX = 'groupId'

# TODO: rm this model?

defaultGroupRecordType = (groupRecordType) ->
  unless groupRecordType?
    return null

  _.defaults groupRecordType, {
    id: uuid.v4()
    creatorId: null
    groupId: null
    name: null
    timeScale: null
    time: new Date()
  }

GROUP_RECORD_TYPES_TABLE = 'group_record_types'

class GroupRecordTypeModel
  RETHINK_TABLES: [
    {
      name: GROUP_RECORD_TYPES_TABLE
      indexes: [
        {
          name: GROUP_ID_INDEX
        }
      ]
    }
  ]

  create: (groupRecordType) ->
    groupRecordType = defaultGroupRecordType groupRecordType

    r.table GROUP_RECORD_TYPES_TABLE
    .insert groupRecordType
    .run()
    .then ->
      groupRecordType

  getById: (id) ->
    r.table GROUP_RECORD_TYPES_TABLE
    .get id
    .run()
    .then defaultGroupRecordType

  deleteById: (id) ->
    r.table GROUP_RECORD_TYPES_TABLE
    .get id
    .delete()
    .run()
    .then -> null

  getAllByGroupId: (groupId) ->
    r.table GROUP_RECORD_TYPES_TABLE
    .getAll groupId, {index: GROUP_ID_INDEX}
    .run()



module.exports = new GroupRecordTypeModel()
