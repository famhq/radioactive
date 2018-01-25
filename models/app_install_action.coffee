_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

config = require '../config'
cknex = require '../services/cknex'

ONE_DAY_SECONDS = 3600 * 24

defaultAppInstallAction = (appInstallAction) ->
  unless appInstallAction?
    return null

  appInstallAction


tables = [
  {
    name: 'app_install_actions'
    keyspace: 'starfire'
    fields:
      ip: 'text'
      path: 'text'
    primaryKey:
      partitionKey: ['ip']
      clusteringColumns: null
  }
]

class AppInstallActionModel
  SCYLLA_TABLES: tables

  upsert: (appInstallAction) ->
    appInstallAction = defaultAppInstallAction(
      appInstallAction
    )

    cknex().update 'app_install_actions'
    .set _.omit appInstallAction, [
      'ip'
    ]
    .andWhere 'ip', '=', appInstallAction.ip
    .usingTTL ONE_DAY_SECONDS
    .run()
    .then ->
      appInstallAction

  getByIp: (ip) ->
    cknex().select '*'
    .from 'app_install_actions'
    .where 'ip', '=', ip
    .limit 1
    .run {isSingle: true}

module.exports = new AppInstallActionModel()
