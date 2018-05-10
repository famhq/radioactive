# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS = config.GROUPS

DEFAULT_STICKER_ODDS = [
  {type: 'sticker', rarity: 'common', odds: 0.8, tier: 'premium'}
  {type: 'sticker', rarity: 'rare', odds: 0.13, tier: 'premium'}
  {type: 'sticker', rarity: 'epic', odds: 0.05, tier: 'premium'}
  {type: 'sticker', rarity: 'legendary', odds: 0.02, tier: 'premium'}
]
DEFAULT_BASE_ODDS = [
  {type: 'sticker', rarity: 'common', odds: 0.8, tier: 'base'}
  {type: 'sticker', rarity: 'rare', odds: 0.13, tier: 'base'}
  {type: 'sticker', rarity: 'epic', odds: 0.05, tier: 'base'}
  {type: 'sticker', rarity: 'legendary', odds: 0.02, tier: 'base'}
]

items =
  nan_currency: {name: 'NyteBucks', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'currency'}

  nan_gg: {name: 'GG', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_get_rekt: {name: 'Get rekt', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_geet: {name: 'Geet', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_snipe1: {name: 'Snipe 1', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_snipe2: {name: 'Snipe 2', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_snipe3: {name: 'Snipe 3', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_snipe4: {name: 'Snipe 4', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  nan_gfuel: {name: 'G FUEL', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', tier: 'base', type: 'sticker'}
  nan: {name: 'NyteFish', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', tier: 'base', type: 'sticker'}
  nan_ice_fish: {name: 'Ice Fish', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', tier: 'base', type: 'sticker'}
  nan_g1: {name: 'G1', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', tier: 'premium', type: 'sticker'}
  nan_g2: {name: 'G2', groupId: GROUPS.NICKATNYTE.ID, rarity: 'legendary', tier: 'premium', type: 'sticker'}
  nan_wow: {name: 'Wow', groupId: GROUPS.NICKATNYTE.ID, rarity: 'legendary', tier: 'base', type: 'sticker'}

  nan_cheezeit: {name: 'Cheezeit', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  nan_kiss: {name: 'Kiss', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  nan_shook: {name: 'Shook', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  nan_clue: {name: 'Clue', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  nan_nuts: {name: 'Nuts', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  nan_nytewitch: {name: 'Nytewitch', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', tier: 'premium', type: 'sticker'}
  nan_ah: {name: 'Ah', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', tier: 'premium', type: 'sticker'}
  nan_mat: {name: 'Mat', groupId: GROUPS.NICKATNYTE.ID, rarity: 'rare', tier: 'premium', type: 'sticker'}
  nan_new: {name: 'New', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', tier: 'premium', type: 'sticker'}
  nan_terrify: {name: 'Terrify', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', tier: 'premium', type: 'sticker'}
  nan_unicorn: {name: 'Unicorn', groupId: GROUPS.NICKATNYTE.ID, rarity: 'legendary', tier: 'premium', type: 'sticker'}
  nan_rip: {name: 'RIP', groupId: GROUPS.NICKATNYTE.ID, rarity: 'legendary', tier: 'premium', type: 'sticker'}

  nan_name_color_base_7_days: {
    name: 'Name color (7d)', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', tier: 'base', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorBase'
  }
  nan_name_color_premium_7_days: {
    name: 'Premium name color (7d)', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', tier: 'premium', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorPremium'
  }

  nan_chest: {
    name: 'NickAtNyte Premium Chest', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', type: 'chest'
    data:
      keyRequired: 'nan_key'
      odds: DEFAULT_STICKER_ODDS
      count: 3
      backKey: 'nan'
  }
  nan_key: {
    name: 'NickAtNyte Premium Key', groupId: GROUPS.NICKATNYTE.ID, rarity: 'epic', type: 'key'
    data:
      chestKey: 'nan_chest'
  }
  nan_base_chest: {
    name: 'NickAtNyte Base Chest', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'nan_base_key'
      odds: DEFAULT_BASE_ODDS
      count: 3
      backKey: 'nan'
  }
  nan_base_key: {
    name: 'NickAtNyte Base Key', groupId: GROUPS.NICKATNYTE.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'nan_base_chest'
  }






  tv_currency: {name: 'Positivity', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', type: 'currency'}

  tv: {name: '#TheViewage', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  tv_ackha: {name: 'AckHa', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  tv_been: {name: 'Been', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  tv_explo: {name: 'Explo', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  tv_disgust: {name: 'Disgust', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'rare', tier: 'base', type: 'sticker'}
  tv_fb: {name: 'FB', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'rare', tier: 'base', type: 'sticker'}
  tv_geeg: {name: 'GeeG', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'rare', tier: 'base', type: 'sticker'}
  tv_dathwa: {name: 'Dathwa', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'legendary', tier: 'base', type: 'sticker'}

  tv_rage: {name: 'Rage', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  tv_sit: {name: 'Sit', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  tv_yeet: {name: 'Yeet', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  tv_yg: {name: 'YG', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  tv_ppp: {name: 'PPP', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'rare', tier: 'premium', type: 'sticker'}
  tv_booty: {name: 'Booty', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'rare', tier: 'premium', type: 'sticker'}
  tv_pppp: {name: 'PPPP', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'epic', tier: 'premium', type: 'sticker'}
  tv_gu: {name: 'Grow up', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'legendary', tier: 'premium', type: 'sticker'}

  tv_name_color_base_7_days: {
    name: 'Name color (7d)', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', tier: 'base', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorBase'
  }
  tv_name_color_premium_7_days: {
    name: 'Premium name color (7d)', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'epic', tier: 'premium', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorPremium'
  }

  tv_chest: {
    name: '#TheViewage Premium Chest', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'epic', type: 'chest'
    data:
      keyRequired: 'tv_key'
      odds: DEFAULT_STICKER_ODDS
      count: 3
      backKey: 'tv'
  }
  tv_key: {
    name: '#TheViewage Premium Key', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'epic', type: 'key'
    data:
      chestKey: 'tv_chest'
  }
  tv_base_chest: {
    name: '#TheViewage Base Chest', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', type: 'chest'
    data:
      keyRequired: 'tv_base_key'
      odds: DEFAULT_BASE_ODDS
      count: 3
      backKey: 'tv'
  }
  tv_base_key: {
    name: '#TheViewage Base Key', groupId: GROUPS.THE_VIEWAGE.ID, rarity: 'common', type: 'key'
    data:
      chestKey: 'tv_base_chest'
  }




  # tq: {name: 'Team Queso', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'starter', type: 'sticker'}
  # tq_adrian_piedra: {name: 'TQ Adrian Piedra', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'sticker'}
  # tq_coltonw83: {name: 'TQ DiegoB', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'sticker'}
  # tq_diegob: {name: 'TQ Coltonw83', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'sticker'}
  # tq_chest: {
  #   name: 'Team Queso Chest', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'chest'
  #   data:
  #     keyRequired: 'tq_key'
  #     odds: DEFAULT_STICKER_ODDS
  #     count: 3
  #     backKey: 'tq'
  # }
  # tq_key: {
  #   name: 'Team Queso Key', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'key'
  #   data:
  #     chestKey: 'tq_chest'
  # }
  # tq_starter_chest: {
  #   name: 'Team Queso Starter Chest', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'chest'
  #   data:
  #     keyRequired: 'tq_starter_key'
  #     odds: [{type: 'sticker', rarity: 'starter', odds: 1}]
  #     count: 1
  #     backKey: 'tq'
  # }
  # tq_starter_key: {
  #   name: 'Team Queso Starter Key', groupId: GROUPS.TEAM_QUESO.ID, rarity: 'common', type: 'key'
  #   data:
  #     chestKey: 'tq_starter_chest'
  # }





  # ninja_currency: {name: 'Stars', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'currency'}
  #
  # ninja: {name: 'Ninja', groupId: GROUPS.NINJA.ID, rarity: 'starter', tier: 'base', type: 'sticker'}
  # ninja_aim: {name: 'Ninja Aim', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  # ninja_hype: {name: 'Ninja Hype', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  # ninja_pon: {name: 'Ninja Pon', groupId: GROUPS.NINJA.ID, rarity: 'epic', tier: 'base', type: 'sticker'}
  # ninja_creep: {name: 'Ninja Creep', groupId: GROUPS.NINJA.ID, rarity: 'legendary', tier: 'base', type: 'sticker'}
  # ninja_blast1: {name: 'Ninja Blast 1', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  # ninja_blast2: {name: 'Ninja Blast 2', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  # ninja_blast3: {name: 'Ninja Blast 3', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  # ninja_pon: {name: 'Ninja Pon', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'sticker'}
  #
  # ninja_amazing: {name: 'Ninja Amazing', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_aww: {name: 'Ninja Aww', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_clap: {name: 'Ninja Clap', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_cry: {name: 'Ninja Cry', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_disco: {name: 'Ninja Disco', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_h: {name: 'Ninja H', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_iq: {name: 'Ninja IQ', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_s: {name: 'Ninja S', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_shrug: {name: 'Ninja Shrug', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  # ninja_wifey: {name: 'Ninja Wifey', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'premium', type: 'sticker'}
  #
  # ninja_name_color_base_7_days: {
  #   name: 'Name color (7d)', groupId: GROUPS.NINJA.ID, rarity: 'common', tier: 'base', type: 'consumable'
  #   data:
  #     duration: 3600 * 24 * 7
  #     upgradeType: 'nameColorBase'
  # }
  # ninja_name_color_premium_7_days: {
  #   name: 'Premium name color (7d)', groupId: GROUPS.NINJA.ID, rarity: 'epic', tier: 'premium', type: 'consumable'
  #   data:
  #     duration: 3600 * 24 * 7
  #     upgradeType: 'nameColorPremium'
  # }
  # ninja_chest: {
  #   name: 'Ninja Chest', groupId: GROUPS.NINJA.ID, rarity: 'epic', type: 'chest'
  #   data:
  #     keyRequired: 'ninja_key'
  #     odds: DEFAULT_STICKER_ODDS
  #     count: 3
  #     backKey: 'ninja'
  # }
  # ninja_key: {
  #   name: 'Ninja Key', groupId: GROUPS.NINJA.ID, rarity: 'epic', type: 'key'
  #   data:
  #     chestKey: 'ninja_chest'
  # }
  # ninja_base_chest: {
  #   name: 'Ninja Starter Chest', groupId: GROUPS.NINJA.ID, rarity: 'common', type: 'chest'
  #   data:
  #     keyRequired: 'ninja_base_key'
  #     odds: DEFAULT_BASE_ODDS
  #     count: 3
  #     backKey: 'ninja'
  # }
  # ninja_base_key: {
  #   name: 'Ninja Starter Key', groupId: GROUPS.NINJA.ID, rarity: 'common', type: 'key'
  #   data:
  #     chestKey: 'ninja_base_chest'
  # }



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



  cr_es_currency: {name: 'Famonedas CR', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'currency'}

  cr_es_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'epic', type: 'sticker'}
  cr_es_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'rare', type: 'sticker'}
  cr_es_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', type: 'sticker'}
  cr_es_name_color_base_7_days: {
    name: 'Nombre de color (7d)', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'common', tier: 'base', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorBase'
  }
  cr_es_name_color_premium_7_days: {
    name: 'Prima nombre de color (7d)', groupId: GROUPS.CLASH_ROYALE_ES.ID, rarity: 'epic', tier: 'premium', type: 'consumable'
    data:
      duration: 3600 * 24 * 7
      upgradeType: 'nameColorPremium'
  }
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

module.exports = _.map items, (value, key) -> _.defaults value, {key, tier: 'base'}

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
