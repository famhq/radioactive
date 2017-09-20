_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

r = require '../services/rethinkdb'

ADDONS_TABLE = 'addons'
CREATOR_ID_INDEX = 'creatorId'
SCORE_INDEX = 'score'
ADD_TIME_INDEX = 'addTime'
LAST_UPDATE_TIME_INDEX = 'lastUpdateTime'

defaultAddon = (addon) ->
  unless addon?
    return null

  _.defaults addon, {
    id: uuid.v4()
    creatorId: null
    key: null
    url: null
    iconUrl: null
    translations: {} # TODO
    upvotes: 0
    downvotes: 0
    score: 0
    data: {}
    lastUpdateTime: new Date()
    addTime: new Date()
  }

class AddonModel
  RETHINK_TABLES: [
    {
      name: ADDONS_TABLE
      options: {}
      indexes: [
        {name: CREATOR_ID_INDEX}
        {name: SCORE_INDEX}
        {name: ADD_TIME_INDEX}
        {name: LAST_UPDATE_TIME_INDEX}
      ]
    }
  ]

  create: (addon) ->
    addon = defaultAddon addon

    r.table ADDONS_TABLE
    .insert addon
    .run()
    .then ->
      addon

  getById: (id) ->
    r.table ADDONS_TABLE
    .get id
    .run()
    .then defaultAddon

  updateById: (id, diff) ->
    r.table ADDONS_TABLE
    .get id
    .update diff
    .run()

  sanitize: _.curry (requesterId, addon) ->
    _.pick addon, [
      'id'
      'creatorId'
      'creator'
      'iconUrl'
      'myVote'
      'score'
      'upvotes'
      'downvotes'
      'addTime'
      'lastUpdateTime'
      'embedded'
    ]

module.exports = new AddonModel()
