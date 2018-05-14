_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

TwitterService = require '../services/twitter'
EarnAction = require '../models/earn_action'
config = require '../config'

class SocialMediaCtrl
  getLastTweetByGroupId: ({groupId}, {user}) ->
    twitterUsername = 'cdnthe3rd' # TODO
    TwitterService.get 'statuses/user_timeline', {screen_name: twitterUsername}
    .then (tweets) ->
      tweets?.data?[3]

  logAction: ({id, groupId}, {user}) ->
    EarnAction.completeActionByGroupIdAndUserId(
      groupId
      user.id
      'streamRetweet'
    )

module.exports = new SocialMediaCtrl()
