_ = require 'lodash'
Promise = require 'bluebird'
router = require 'exoid-router'

TwitterService = require '../services/twitter'
config = require '../config'

class SocialMediaCtrl
  getLastTweetByGroupId: ({groupId}, {user}) ->
    twitterUsername = 'cdnthe3rd' # TODO
    TwitterService.get 'statuses/user_timeline', {screen_name: twitterUsername}
    .then (tweets) ->
      tweets?.data?[3]

module.exports = new SocialMediaCtrl()
