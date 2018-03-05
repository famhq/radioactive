# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS = config.GROUPS

DEFAULT_STICKER_ODDS = [
  {type: 'sticker', rarity: 'common', odds: 0.8}
  {type: 'sticker', rarity: 'rare', odds: 0.13}
  {type: 'sticker', rarity: 'epic', odds: 0.05}
  {type: 'sticker', rarity: 'legendary', odds: 0.02}
]

items =
  nan: {name: 'NickAtNyte', groupId: GROUPS.NICKATNYTE.ID, rarity: 'starter', type: 'sticker'}
  nan_gg: {name: 'GG', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'sticker'}
  # nan_nyte: {name: 'Nyte', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', type: 'sticker'}
  nan_gfuel: {name: 'G FUEL', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', type: 'sticker'}
  nan_get_rekt: {name: 'Get rekt', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', type: 'sticker'}
  nan_wow: {name: 'Wow', groupId: GROUPS.NICKATNYTE.ID, rarity: 'legendary', type: 'sticker'}
  nan_chest: {
    name: 'NickAtNyte Chest', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'nan_key'
      odds: DEFAULT_STICKER_ODDS
      count: 3
      backKey: 'nan'
  }
  nan_key: {
    name: 'NickAtNyte Key', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'nan_chest'
  }
  nan_starter_chest: {
    name: 'NickAtNyte Starter Chest', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'nan_starter_key'
      odds: [{type: 'sticker', rarity: 'starter', odds: 1}]
      count: 1
      backKey: 'nan'
  }
  nan_starter_key: {
    name: 'NickAtNyte Starter Key', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'nan_starter_chest'
  }

  ph: {name: 'PlayHard', groupId: GROUPS.PLAY_HARD.ID, rarity: 'starter', type: 'sticker'}
  ph_bruno: {name: 'Bruno', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_huum: {name: 'Huum', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_surpreso: {name: 'Surpreso', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_feliz: {name: 'Feliz', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_bora: {name: 'Bora', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_assustadao: {name: 'Assustadao', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_aleluia: {name: 'Aleluia', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_tenso: {name: 'Tenso', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'sticker'}
  ph_hmm: {name: 'Hmm', groupId: GROUPS.PLAY_HARD.ID, rarity: 'rare', type: 'sticker'}
  ph_uau: {name: 'Uau', groupId: GROUPS.PLAY_HARD.ID, rarity: 'rare', type: 'sticker'}
  ph_love: {name: 'Love', groupId: GROUPS.PLAY_HARD.ID, rarity: 'rare', type: 'sticker'}
  ph_voa: {name: 'Voa', groupId: GROUPS.PLAY_HARD.ID, rarity: 'epic', type: 'sticker'}
  ph_god: {name: 'God', groupId: GROUPS.PLAY_HARD.ID, rarity: 'legendary', type: 'sticker'}
  ph_badge_7_days: {
    name: 'Badge for 7 days', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'fireBadge'
  }
  ph_chest: {
    name: 'PH Chest', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'ph_key'
      odds: DEFAULT_STICKER_ODDS
      count: 3
      backKey: 'ph'
  }
  ph_key: {
    name: 'PH Key', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'ph_chest'
  }
  ph_starter_chest: {
    name: 'PH Starter Chest', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'ph_starter_key'
      odds: [{type: 'sticker', rarity: 'starter', odds: 1}]
      count: 1
      backKey: 'ph'
  }
  ph_starter_key: {
    name: 'PH Starter Key', groupId: GROUPS.PLAY_HARD.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'ph_starter_chest'
  }

  cr_en_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
  cr_en_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
  cr_en_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
  cr_en_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'epic', type: 'sticker'}
  cr_en_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'rare', type: 'sticker'}
  cr_en_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
  cr_en_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
  cr_en_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}



  cr_es_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'epic', type: 'sticker'}
  cr_es_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'rare', type: 'sticker'}
  cr_es_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  # cr_es_scratch: {
  #   name: 'CR scratch', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'scratch'
  #   data:
  #     coinRequired: 'cr_es_coin'
  #     odds: DEFAULT_STICKER_ODDS
  # }
  # cr_es_coin: {
  #   name: 'CR Coin', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'coin'
  #   data:
  #     scratchItemKey: 'cr_es_scratch'
  # }



  cr_pt_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}
  cr_pt_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}
  cr_pt_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}
  cr_pt_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'epic', type: 'sticker'}
  cr_pt_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'rare', type: 'sticker'}
  cr_pt_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}
  cr_pt_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}
  cr_pt_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PT.ID, rarity: 'common', type: 'sticker'}

  cr_pl_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}
  cr_pl_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}
  cr_pl_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}
  cr_pl_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'epic', type: 'sticker'}
  cr_pl_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'rare', type: 'sticker'}
  cr_pl_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}
  cr_pl_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}
  cr_pl_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PL.ID, rarity: 'common', type: 'sticker'}

  # legacy items earned before 11/21
  sf_logo: {name: 'Starfire Logo', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}
  cr_angry: {name: 'CR Angry', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}
  cr_crying: {name: 'CR Crying', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}
  cr_laughing: {name: 'CR Laughing', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'epic', type: 'sticker'}
  cr_shop_goblin: {name: 'CR Shop Goblin', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'rare', type: 'sticker'}
  cr_thumbs_up: {name: 'CR Thumbs Up', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}
  cr_thumb: {name: 'CR Thumb', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}
  cr_trophy: {name: 'CR Trophy', groupId: config.LEGACY_CLASH_ROYALE_ID, rarity: 'common', type: 'sticker'}

module.exports = _.map items, (value, key) -> _.defaults {key}, value

# cr_barbarian: {name: 'CR Barbarian', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'epic', type: 'sticker'}
# cr_blue_king: {name: 'CR Blue King', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
# cr_epic_chest: {name: 'CR Epic Chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'epic', type: 'sticker'}
# cr_giant_chest: {name: 'CR Giant Chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'rare', type: 'sticker'}
# cr_goblin: {name: 'CR Goblin', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'rare', type: 'sticker'}
# cr_gold_chest: {name: 'CR Gold Chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
# cr_knight: {name: 'CR Knight', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'rare', type: 'sticker'}
# cr_magical_chest: {name: 'CR Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'rare', type: 'sticker'}
# cr_red_king: {name: 'CR Red King', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
# cr_silver_chest: {name: 'CR Silver chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'common', type: 'sticker'}
# cr_smc: {name: 'CR Super Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN.ID, rarity: 'legendary', type: 'sticker'}

# coffeelint: enable=max_line_length,cyclomatic_complexity
