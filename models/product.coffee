_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
config = require '../config'

tables = [
  {
    name: 'products_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      key: 'text'
      name: 'text'
      type: 'text' # pack | general
      data: 'text'
      cost: 'int'
    primaryKey:
      partitionKey: ['groupId']
      clusteringColumns: ['key']
  }
  {
    name: 'products_by_key'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      key: 'text'
      name: 'text'
      type: 'text' # pack | general
      data: 'text'
      cost: 'int'
    primaryKey:
      partitionKey: ['key']
  }
]

defaultProduct = (product) ->
  unless product?
    return null

  product = _.cloneDeep product
  product.data = JSON.stringify product.data
  product

defaultProductOutput = (product) ->
  unless product?
    return null

  product.data = try
    JSON.parse product.data
  catch
    {}

  product

class ProductModel
  SCYLLA_TABLES: tables

  batchUpsert: (products) =>
    Promise.map products, (product) =>
      @upsert product, {skipRun: true}

  getAllByGroupId: (groupId) ->
    cknex().select '*'
    .from 'products_by_groupId'
    .where 'groupId', '=', groupId
    .run()
    .map defaultProductOutput

  getByKey: (key) ->
    cknex().select '*'
    .from 'products_by_key'
    .where 'key', '=', key
    .run {isSingle: true}
    .then defaultProductOutput

  upsert: (product, {skipRun} = {}) ->
    product = defaultProduct product

    Promise.all [
      cknex().update 'products_by_groupId'
      .set _.omit product, ['groupId', 'key']
      .where 'groupId', '=', product.groupId
      .andWhere 'key', '=', product.key
      .run()

      cknex().update 'products_by_key'
      .set _.omit product, ['key']
      .where 'key', '=', product.key
      .run()
    ]

module.exports = new ProductModel()
