# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

###
user_items
{
  userId, itemId, itemLevel (size)
}
###

items = [].concat(
  # {name: 'PlayHard', key: 'ph', groupId: config.GROUPS.PLAY_HARD, rarity: 'common'}
  # {name: 'Bruno', key: 'bruno', groupId: config.GROUPS.PLAY_HARD, rarity: 'common'}
  {name: 'Starfire Logo', key: 'sf_logo', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  {name: 'CR Angry', key: 'cr_angry', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  # {name: 'CR Barbarian', key: 'cr_barbarian', groupId: config.GROUPS.STARFIRE, rarity: 'epic'}
  {name: 'CR Crying', key: 'cr_crying', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  # {name: 'CR Blue King', key: 'cr_blue_king', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  # {name: 'CR Epic Chest', key: 'cr_epic_chest', groupId: config.GROUPS.STARFIRE, rarity: 'epic'}
  # {name: 'CR Giant Chest', key: 'cr_giant_chest', groupId: config.GROUPS.STARFIRE, rarity: 'rare'}
  # {name: 'CR Goblin', key: 'cr_goblin', groupId: config.GROUPS.STARFIRE, rarity: 'rare'}
  # {name: 'CR Gold Chest', key: 'cr_gold_chest', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  # {name: 'CR Knight', key: 'cr_knight', groupId: config.GROUPS.STARFIRE, rarity: 'rare'}
  {name: 'CR Laughing', key: 'cr_laughing', groupId: config.GROUPS.STARFIRE, rarity: 'epic'}
  # {name: 'CR Magical Chest', key: 'cr_magical_chest', groupId: config.GROUPS.STARFIRE, rarity: 'rare'}
  # {name: 'CR Red King', key: 'cr_red_king', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  {name: 'CR Shop Goblin', key: 'cr_shop_goblin', groupId: config.GROUPS.STARFIRE, rarity: 'rare'}
  # {name: 'CR Silver chest', key: 'cr_silver_chest', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  # {name: 'CR Super Magical Chest', key: 'cr_smc', groupId: config.GROUPS.STARFIRE, rarity: 'legendary'}
  {name: 'CR Thumbs Up', key: 'cr_thumbs_up', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  {name: 'CR Thumb', key: 'cr_thumb', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
  {name: 'CR Trophy', key: 'cr_trophy', groupId: config.GROUPS.STARFIRE, rarity: 'common'}
)

if _.uniq(items).length isnt items.length
  throw Error 'duplicate key'

module.exports = items
# coffeelint: enable=max_line_length,cyclomatic_complexity
