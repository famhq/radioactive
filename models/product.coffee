_ = require 'lodash'
uuid = require 'node-uuid'
Promise = require 'bluebird'

cknex = require '../services/cknex'
config = require '../config'

# ALTER TABLE starfire."products_by_groupId" ADD currency text;
# ALTER TABLE starfire."products_by_key" ADD currency text;

tables = [
  {
    name: 'products_by_groupId'
    keyspace: 'starfire'
    fields:
      groupId: 'uuid'
      key: 'text'
      name: 'text'
      type: 'text' # pack | general
      currency: 'text'
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
      currency: 'text'
      data: 'text'
      cost: 'int'
    primaryKey:
      partitionKey: ['key']
  }
  {
    # stored with ttl
    name: 'product_locks'
    keyspace: 'starfire'
    fields:
      userId: 'uuid'
      groupId: 'uuid'
      productKey: 'text'
      time: 'timestamp'
    primaryKey:
      partitionKey: ['userId']
      clusteringColumns: ['groupId', 'productKey']
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
      @upsert product

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

  getLockByProductAndUserId: (product, userId) ->
    cknex().select '*'
    .from 'product_locks'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', product.groupId
    .andWhere 'productKey', '=', product.key
    .run {isSingle: true}

  getLocksByUserIdAndGroupId: (userId, groupId) ->
    cknex().select 'productKey'
    .ttl 'time'
    .from 'product_locks'
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', groupId
    .run()

  setLockByProductAndUserId: (product, userId) ->
    q = cknex().update 'product_locks'
    .set {time: new Date()}
    .where 'userId', '=', userId
    .andWhere 'groupId', '=', product.groupId
    .andWhere 'productKey', '=', product.key

    if product.data.lockTime isnt 'infinity'
      q = q.usingTTL product.data.lockTime

    q.run()

  upsert: (product) ->
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
