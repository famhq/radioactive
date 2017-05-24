ua = require 'universal-analytics'

config = require '../config'

class StatsService
  sendEvent: (userId, category, action, label) ->
    ga = ua config.GA_ID, userId
    ga.event(category, action, label).send()

module.exports = new StatsService()
