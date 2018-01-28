_ = require 'lodash'

AppInstallAction = require '../models/app_install_action'
config = require '../config'

class AppInstallActionCtrl
  upsert: ({path}, {headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    if config.ENV is config.ENVS.DEV
      ip ?= '000.000.0.000'
    if ip
      AppInstallAction.upsert {ip, path}
    else
      Promise.resolve null

  get: ({path}, {headers, connection}) ->
    ip = headers['x-forwarded-for'] or
          connection.remoteAddress
    if config.ENV is config.ENVS.DEV
      ip ?= '000.000.0.000'

    if ip
      AppInstallAction.getByIp ip
    else
      Promise.resolve null

module.exports = new AppInstallActionCtrl()
