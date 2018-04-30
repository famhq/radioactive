_ = require 'lodash'

Iap = require '../models/iap'

class IapCtrl
  getAllByPlatform: ({platform}, {user}) ->
    Iap.getAllByPlatform platform

module.exports = new IapCtrl()
