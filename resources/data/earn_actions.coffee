# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS = config.GROUPS
ONE_DAY_SECONDS = 3600 * 24
THREE_HOURS_SECONDS = 3600 * 3

# chatMessage, forumComment, videoView, rewardedVideo

actions =
  nan_daily_visit:
    name: 'Daily visit'
    groupId: GROUPS.NICKATNYTE.ID
    action: 'visit'
    data:
      rewards: [
        {currencyAmount: 100, currencyType: 'item', currencyItemKey: 'nan_currency'}
        {currencyAmount: 5, currencyType: 'xp'}
      ]
      button:
        text: 'Claim'
    maxCount: 1
    ttl: ONE_DAY_SECONDS
  nan_daily_chat_message:
    name: 'Daily chat message'
    groupId: GROUPS.NICKATNYTE.ID
    action: 'chatMessage'
    data:
      rewards: [
        {currencyAmount: 100, currencyType: 'item', currencyItemKey: 'nan_currency'}
        {currencyAmount: 5, currencyType: 'xp'}
      ]
      button:
        text: 'Go to chat'
        route:
          key: 'groupChat'
          replacements: {groupId: 'nickatnyte'}
    maxCount: 1
    ttl: ONE_DAY_SECONDS
  nan_daily_video_view:
    name: 'Daily video view'
    groupId: GROUPS.NICKATNYTE.ID
    action: 'videoView'
    data:
      rewards: [
        {currencyAmount: 100, currencyType: 'item', currencyItemKey: 'nan_currency'}
        {currencyAmount: 5, currencyType: 'xp'}
      ]
      button:
        text: 'Go to videos'
        route:
          key: 'groupVideos'
          replacements: {groupId: 'nickatnyte'}
    maxCount: 1
    ttl: ONE_DAY_SECONDS
  nan_rewarded_videos:
    name: 'Watch ad'
    groupId: GROUPS.NICKATNYTE.ID
    action: 'watchAd'
    data:
      rewards: [
        {currencyAmount: 50, currencyType: 'item', currencyItemKey: 'nan_currency'}
        {currencyAmount: 1, currencyType: 'xp'}
      ]
      button:
        text: 'Watch ad'
    maxCount: 3
    ttl: THREE_HOURS_SECONDS

module.exports = _.map actions, (value, key) -> value
