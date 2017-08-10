_ = require 'lodash'
router = require 'exoid-router'

EmailService = require '../services/email'
StatsService = require '../services/stats'
config = require '../config'

class NpsCtrl
  create: ({score, comment} = {}, {user}) ->
    if comment
      EmailService.send {
        to: EmailService.EMAILS.EVERYONE
        subject: "Starfire NPS (#{score})"
        text: "#{comment}"
      }
    StatsService.sendEvent user?.id, 'nps', score

module.exports = new NpsCtrl()
