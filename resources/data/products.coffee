# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS =
  PLAY_HARD: 'ad25e866-c187-44fc-bdb5-df9fcc4c6a42'
  STARFIRE: config.CLASH_ROYALE_ID

# name done via lang file
products = [].concat(
  {
    key: 'ph_pack1', type: 'pack', groupId: GROUPS.PLAY_HARD
    cost: 100 # 10c
    data:
      count: 1
      odds: [
        {rarity: 'common', odds: 0.8}
        {rarity: 'rare', odds: 0.13}
        {rarity: 'epic', odds: 0.05}
        {rarity: 'legendary', odds: 0.02}
      ]
  }
  {
    key: 'starfire_pack1', type: 'pack', groupId: GROUPS.STARFIRE
    cost: 100 # 10c
    data:
      count: 1
      odds: [
        {rarity: 'common', odds: 0.8}
        {rarity: 'rare', odds: 0.13}
        {rarity: 'epic', odds: 0.05}
        {rarity: 'legendary', odds: 0.02}
      ]
  }
  {
    key: 'starfire_pack3', type: 'pack', groupId: GROUPS.STARFIRE
    cost: 250 # 25c
    data:
      count: 3
      odds: [
        {rarity: 'common', odds: 0.8}
        {rarity: 'rare', odds: 0.13}
        {rarity: 'epic', odds: 0.05}
        {rarity: 'legendary', odds: 0.02}
      ]
  }
  # {key: 'no_ads_for_day', type: 'general', groupId: GROUPS.STARFIRE, cost: 50}
  {key: 'google_play_10', type: 'general', groupId: GROUPS.STARFIRE, cost: 15000}
  {key: 'visa_10', type: 'general', groupId: GROUPS.STARFIRE, cost: 15000}
)

if _.uniq(products).length isnt products.length
  throw Error 'duplicate key'

module.exports = products
# coffeelint: enable=max_line_length,cyclomatic_complexity
