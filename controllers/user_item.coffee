_ = require 'lodash'
router = require 'exoid-router'

UserItem = require '../models/user_item'
EmbedService = require '../services/embed'
CacheService = require '../services/cache'
config = require '../config'

defaultEmbed = [
  EmbedService.TYPES.USER_ITEM.ITEM
]

TWO_MINUTES_SECONDS = 60 * 2

class UserItemCtrl
  getAll: ({}, {user}) ->
    UserItem.getAllByUserId user.id
    .map EmbedService.embed {embed: defaultEmbed}

  upgradeByItemKey: ({itemKey}, {user}) ->
    prefix = CacheService.LOCK_PREFIXES.UPGRADE_STICKER
    key = "#{prefix}:#{user.id}:#{itemKey}"
    CacheService.lock key, ->
      UserItem.getByUserIdAndItemKey user.id, itemKey
      .then (userItem) ->
        currentLevel = userItem?.itemLevel or 1
        itemLevel = _.find(config.LEVEL_REQUIREMENTS, {
          level: currentLevel + 1
          })
        console.log currentLevel,  userItem?.count, itemLevel?.countRequired
        unless userItem?.count >= itemLevel?.countRequired
          router.throw {status: 400, info: 'not enough stickers'}

        # since level starts at 0 (not 1), we need to add 2 for level 2
        inc = if not userItem.itemLevel then 2 else 1

        UserItem.incrementLevelByItemKeyAndUserId itemKey, user.id, inc
    , {expireSeconds: TWO_MINUTES_SECONDS, unlockWhenCompleted: true}

module.exports = new UserItemCtrl()
