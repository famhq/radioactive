_ = require 'lodash'

Iap = require '../models/iap'

class IapCtrl
  getAllByPlatform: ({platform}, {user}) ->
    console.log 'get'
    Iap.getAllByPlatform platform

module.exports = new IapCtrl()
