_ = require 'lodash'
router = require 'exoid-router'
crypto = require 'crypto'

TimeService = require '../services/time'
EarnAction = require '../models/earn_action'
config = require '../config'

REEDEMABLE_ACTION_KEYS_FROM_CLIENT = ['visit', 'watchAd', 'streamVisit']

class EarnActionCtrl
  incrementByGroupIdAndAction: (options, {user}) ->
    {groupId, action, timestamp, successKey} = options
    if REEDEMABLE_ACTION_KEYS_FROM_CLIENT.indexOf(action) is -1
      router.throw {status: 400, info: 'cannot claim'}

    # if action is 'watchAd'
    #   shasum = crypto.createHmac 'md5', config.NATIVE_SORT_OF_SECRET
    #   shasum.update "#{timestamp}"
    #   compareKey = shasum.digest('hex')
    #   if not timestamp or not successKey or compareKey isnt successKey
    #     router.throw {status: 400, info: 'invalid'}

    EarnAction.completeActionByGroupIdAndUserId(
      groupId, user.id, action
    )

  getAllByGroupId: ({groupId, platform}, {user}) ->
    Promise.all [
      EarnAction.getAllByGroupId groupId
      EarnAction.getAllTransactionsByUserIdAndGroupId(
        user.id, groupId
      )
    ]
    .then ([actions, transactions]) ->
      if platform
        actions = _.filter actions, (action) ->
          if action.data.includedPlatforms and platform
            isIncluded = action.data.includedPlatforms.indexOf(platform) isnt -1
          else
            isIncluded = true
          if action.data.excludedPlatforms and platform
            isExcluded = action.data.excludedPlatforms.indexOf(platform) isnt -1
          else
            isExcluded = false
          isIncluded and not isExcluded

      _.map actions, (action) ->
        action.transaction = _.find transactions, {action: action.action}
        action

module.exports = new EarnActionCtrl()
