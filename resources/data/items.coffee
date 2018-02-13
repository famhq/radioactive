# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS =
  PLAY_HARD: 'ad25e866-c187-44fc-bdb5-df9fcc4c6a42'
  CLASH_ROYALE_EN: '73ed4af0-a2f2-4371-a893-1360d3989708'
  CLASH_ROYALE_ES: '4f26e51e-7f35-41dd-9f21-590c7bb9ce34'
  CLASH_ROYALE_PT: '68acb51a-3e5a-466a-9e31-c93aacd5919e'
  CLASH_ROYALE_PL: '22e9db0b-45be-4c6d-86a5-434b38684db9'
  LEGACY: 'clash-royale'

DEFAULT_STICKER_ODDS = [
  {type: 'sticker', rarity: 'common', odds: 0.8}
  {type: 'sticker', rarity: 'rare', odds: 0.13}
  {type: 'sticker', rarity: 'epic', odds: 0.05}
  {type: 'sticker', rarity: 'legendary', odds: 0.02}
]

items =
  ph: {name: 'PlayHard', groupId: GROUPS.PLAY_HARD, rarity: 'starter', type: 'sticker'}
  ph_bruno: {name: 'Bruno', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_huum: {name: 'Huum', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_surpreso: {name: 'Surpreso', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_feliz: {name: 'Feliz', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_bora: {name: 'Bora', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_assustadao: {name: 'Assustadao', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_aleluia: {name: 'Aleluia', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_tenso: {name: 'Tenso', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'sticker'}
  ph_hmm: {name: 'Hmm', groupId: GROUPS.PLAY_HARD, rarity: 'rare', type: 'sticker'}
  ph_uau: {name: 'Uau', groupId: GROUPS.PLAY_HARD, rarity: 'rare', type: 'sticker'}
  ph_love: {name: 'Love', groupId: GROUPS.PLAY_HARD, rarity: 'rare', type: 'sticker'}
  ph_voa: {name: 'Voa', groupId: GROUPS.PLAY_HARD, rarity: 'epic', type: 'sticker'}
  ph_god: {name: 'God', groupId: GROUPS.PLAY_HARD, rarity: 'legendary', type: 'sticker'}
  ph_badge_7_days: {
    name: 'Badge for 7 days', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'fireBadge'
  }
  ph_scratch: {
    name: 'PH scratch off', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'scratch'
    data:
      coinRequired: 'ph_coin'
      odds: DEFAULT_STICKER_ODDS
  }
  ph_coin: {
    name: 'PH Coin', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'coin'
    data:
      scratchItemKey: 'ph_scratch'
  }
  ph_starter_scratch: {
    name: 'PH scratch off', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'scratch'
    data:
      coinRequired: 'ph_starter_coin'
      odds: [{type: 'sticker', rarity: 'starter', odds: 1}]
  }
  ph_starter_coin: {
    name: 'PH Coin', groupId: GROUPS.PLAY_HARD, rarity: 'common', type: 'coin'
    data:
      scratchItemKey: 'ph_starter_scratch'
  }

  cr_en_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
  cr_en_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
  cr_en_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
  cr_en_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic', type: 'sticker'}
  cr_en_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare', type: 'sticker'}
  cr_en_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
  cr_en_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
  cr_en_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}



  cr_es_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'epic', type: 'sticker'}
  cr_es_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'rare', type: 'sticker'}
  cr_es_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'sticker'}
  cr_es_scratch: {
    name: 'CR scratch', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'scratch'
    data:
      coinRequired: 'cr_es_coin'
      odds: DEFAULT_STICKER_ODDS
  }
  cr_es_coin: {
    name: 'CR Coin', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common', type: 'coin'
    data:
      scratchItemKey: 'cr_es_scratch'
  }



  cr_pt_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}
  cr_pt_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}
  cr_pt_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}
  cr_pt_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'epic', type: 'sticker'}
  cr_pt_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'rare', type: 'sticker'}
  cr_pt_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}
  cr_pt_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}
  cr_pt_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common', type: 'sticker'}

  cr_pl_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}
  cr_pl_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}
  cr_pl_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}
  cr_pl_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'epic', type: 'sticker'}
  cr_pl_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'rare', type: 'sticker'}
  cr_pl_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}
  cr_pl_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}
  cr_pl_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common', type: 'sticker'}

  # legacy items earned before 11/21
  sf_logo: {name: 'Starfire Logo', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}
  cr_angry: {name: 'CR Angry', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}
  cr_crying: {name: 'CR Crying', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}
  cr_laughing: {name: 'CR Laughing', groupId: GROUPS.LEGACY, rarity: 'epic', type: 'sticker'}
  cr_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.LEGACY, rarity: 'rare', type: 'sticker'}
  cr_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}
  cr_thumb: {name: 'CR Thumb', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}
  cr_trophy: {name: 'CR Trophy', groupId: GROUPS.LEGACY, rarity: 'common', type: 'sticker'}

module.exports = _.map items, (value, key) -> _.defaults {key}, value

# cr_barbarian: {name: 'CR Barbarian', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic', type: 'sticker'}
# cr_blue_king: {name: 'CR Blue King', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
# cr_epic_chest: {name: 'CR Epic Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic', type: 'sticker'}
# cr_giant_chest: {name: 'CR Giant Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare', type: 'sticker'}
# cr_goblin: {name: 'CR Goblin', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare', type: 'sticker'}
# cr_gold_chest: {name: 'CR Gold Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
# cr_knight: {name: 'CR Knight', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare', type: 'sticker'}
# cr_magical_chest: {name: 'CR Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare', type: 'sticker'}
# cr_red_king: {name: 'CR Red King', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
# cr_silver_chest: {name: 'CR Silver chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common', type: 'sticker'}
# cr_smc: {name: 'CR Super Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'legendary', type: 'sticker'}

# coffeelint: enable=max_line_length,cyclomatic_complexity
