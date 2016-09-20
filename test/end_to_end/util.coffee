_ = require 'lodash'

login = ->
  (flare) ->
    flare
    .exoid 'auth.login'
    .stash 'me'
    .actor 'me',
      qs:
        'accessToken': ':me.accessToken'
    .as 'me'

module.exports = {
  login
}
