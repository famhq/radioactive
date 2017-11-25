_ = require 'lodash'
router = require 'exoid-router'
crypto = require 'crypto'

TimeService = require '../services/time'
GroupUserXpTransaction = require '../models/group_user_xp_transaction'
config = require '../config'

REEDEMABLE_ACTION_KEYS_FROM_CLIENT = ['dailyVisit', 'rewardedVideos']

class GroupUserXpTransactionCtrl
  incrementByGroupIdAndActionKey: (options, {user}) ->
    {groupId, actionKey, timestamp, successKey} = options
    if REEDEMABLE_ACTION_KEYS_FROM_CLIENT.indexOf(actionKey) is -1
      router.throw {status: 400, info: 'cannot claim'}

    if actionKey is 'rewardedVideos'
      shasum = crypto.createHmac 'md5', config.NATIVE_SORT_OF_SECRET
      shasum.update "#{timestamp}"
      compareKey = shasum.digest('hex')
      if not compareKey or compareKey isnt successKey
        router.throw {status: 400, info: 'invalid'}

    GroupUserXpTransaction.completeActionByGroupIdAndUserId(
      groupId, user.id, actionKey
    )

  getAllByGroupId: ({groupId}, {user}) ->
    scaledTime = TimeService.getScaledTimeByTimeScale 'day'
    GroupUserXpTransaction.getAllByUserIdAndGroupIdAndScaledTime(
      user.id, groupId, scaledTime
    )

module.exports = new GroupUserXpTransactionCtrl()
