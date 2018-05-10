# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

ONE_DAY_SECONDS = 3600 * 24
GROUPS = config.GROUPS
DEFAULT_FREE_PACK_DATA =
  lockTime: ONE_DAY_SECONDS
  count: 1
  odds: [
    {type: 'sticker', rarity: 'common', tier: 'base', odds: 0.8}
    {type: 'sticker', rarity: 'rare', tier: 'base', odds: 0.13}
    {type: 'sticker', rarity: 'epic', tier: 'base', odds: 0.05}
    {type: 'sticker', rarity: 'legendary', tier: 'base', odds: 0.02}
  ]
DEFAULT_1_PACK_DATA =
  count: 1
  odds: [
    {type: 'sticker', rarity: 'common', tier: 'base', odds: 0.8}
    {type: 'sticker', rarity: 'rare', tier: 'base', odds: 0.13}
    {type: 'sticker', rarity: 'epic', tier: 'base', odds: 0.05}
    {type: 'sticker', rarity: 'legendary', tier: 'base', odds: 0.02}
  ]
DEFAULT_3_PACK_DATA =
  count: 3
  odds: [
    {type: 'sticker', rarity: 'common', tier: 'base', odds: 0.8}
    {type: 'sticker', rarity: 'rare', tier: 'base', odds: 0.13}
    {type: 'sticker', rarity: 'epic', tier: 'base', odds: 0.05}
    {type: 'sticker', rarity: 'legendary', tier: 'base', odds: 0.02}
  ]

products =
  # ph_shout_out_raffle: {
  #   type: 'raffle'
  #   groupId: GROUPS.PLAY_HARD.ID
  #   name: 'PlayHard Raffle Ticket'
  #   cost: 50 # 5c
  #   data:
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/products/ph_shout_out_raffle.png'
  #     backgroundColor: '#ff7f00'
  #     info: '1 raffle ticket. On Feburary 2nd, 1 ticket will be selected at random
  #           and the winning user will get a shoutout in Bruno\'s video on the 3rd'
  # }

  # ph_pack1: {
  #   type: 'pack'
  #   groupId: GROUPS.PLAY_HARD.ID
  #   name: 'Pacote de emojis PH (1)'
  #   cost: 100 # 10c
  #   data: _.defaults {
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ph_1.png'
  #     backgroundColor: '#F44336'
  #   }, DEFAULT_1_PACK_DATA
  # }
  # ph_pack3: {
  #   type: 'pack'
  #   groupId: GROUPS.PLAY_HARD.ID
  #   name: 'Pacote de emojis PH (3)'
  #   cost: 250 # 25c
  #   data: _.defaults {
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ph_3.png'
  #     backgroundColor: '#2196F3'
  #   }, DEFAULT_3_PACK_DATA
  # }
  ph_google_play_30: {
    name: '30 BRL Google Play'
    type: 'general'
    groupId: GROUPS.PLAY_HARD.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  ph_visa_10: {
    name: '$10 USD Visa Gift Card'
    type: 'general'
    groupId: GROUPS.PLAY_HARD.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }
  ph_badge: {
    name: 'Distintivo "fire" no nome'
    type: 'pack'
    groupId: GROUPS.PLAY_HARD.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/items/ph_badge_7_days_large.png'
      backgroundColor: '#333'
      count: 1
      itemKeys: ['ph_badge_7_days']
  }
  ph_key: {
    name: 'PH Key'
    type: 'pack'
    groupId: GROUPS.PLAY_HARD.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ph_key.png'
      backgroundColor: '#2196F3'
      count: 1
      itemKeys: ['ph_key']
  }
  ph_chest: {
    type: 'pack'
    groupId: GROUPS.PLAY_HARD.ID
    name: 'Free Chest'
    cost: 0
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ph_chest.png'
      backgroundColor: '#9C27B0'
      lockTime: ONE_DAY_SECONDS
      count: 1
      itemKeys: ['ph_chest']
  }
  ph_starter_chest: {
    type: 'pack'
    groupId: GROUPS.PLAY_HARD.ID
    name: 'PH Starter Pack'
    cost: 0
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ph_starter_chest.png'
      backgroundColor: '#F44336'
      lockTime: 'infinity'
      count: 2
      itemKeys: ['ph_starter_chest', 'ph_starter_key']
  }
  # ph_send_message: {
  #   name: 'Envie uma mensagem para Bruno'
  #   type: 'general'
  #   groupId: GROUPS.PLAY_HARD.ID
  #   cost: 1000
  # }

  # NICKATNYTE
  nan_key: {
    name: 'NickAtNyte Premium Key', type: 'pack', groupId: GROUPS.NICKATNYTE.ID, cost: 200, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/nan/nan_key.png'
      backgroundColor: '#2196F3'
      count: 1
      itemKeys: ['nan_key']
  }
  nan_base_key: {
    name: 'NickAtNyte Base Key', type: 'pack', groupId: GROUPS.NICKATNYTE.ID, cost: 200, currency: 'nan_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/nan/nan_base_key.png'
      backgroundColor: '#F44336'
      count: 1
      itemKeys: ['nan_base_key']
  }
  nan_base_chest: {
    type: 'pack', groupId: GROUPS.NICKATNYTE.ID, name: 'Daily Free Chests', cost: 0, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/nan/nan_base_chest.png'
      backgroundColor: '#9C27B0'
      lockTime: ONE_DAY_SECONDS
      count: 2
      itemKeys: ['nan_chest', 'nan_base_chest']
  }
  nan_name_color_base_7_days: {
    name: 'Name color (7d)'
    type: 'pack'
    groupId: GROUPS.NICKATNYTE.ID
    cost: 500
    currency: 'nan_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/nan/nan_name_color_base_7_days.png'
      backgroundColor: '#333'
      count: 1
      itemKeys: ['nan_name_color_base_7_days']
  }
  nan_name_color_premium_7_days: {
    name: 'Name color (premium, 7d)'
    type: 'pack'
    groupId: GROUPS.NICKATNYTE.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/nan/nan_name_color_premium_7_days.png'
      backgroundColor: '#eeeeee'
      count: 1
      itemKeys: ['nan_name_color_premium_7_days']
  }

  # TEAM QUESO
  tq_key: {
    name: 'Team Queso Key', type: 'pack', groupId: GROUPS.TEAM_QUESO.ID, cost: 200, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tq_key.png'
      backgroundColor: '#2196F3'
      count: 1
      itemKeys: ['tq_key']
  }
  tq_chest: {
    type: 'pack', groupId: GROUPS.TEAM_QUESO.ID, name: 'Team Queso Chest', cost: 0, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tq_chest.png'
      backgroundColor: '#9C27B0'
      lockTime: ONE_DAY_SECONDS
      count: 1
      itemKeys: ['tq_chest']
  }
  tq_starter_chest: {
    type: 'pack', groupId: GROUPS.TEAM_QUESO.ID, name: 'Team Queso Starter Pack', cost: 0, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tq_starter_chest.png'
      backgroundColor: '#F44336'
      lockTime: 'infinity'
      count: 2
      itemKeys: ['tq_starter_chest', 'tq_starter_key']
  }

  # NINJA
  ninja_key: {
    name: 'Ninja Premium Key', type: 'pack', groupId: GROUPS.NINJA.ID, cost: 200, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ninja/ninja_key.png'
      backgroundColor: '#2196F3'
      count: 1
      itemKeys: ['ninja_key']
  }
  ninja_base_key: {
    name: 'Ninja Base Key', type: 'pack', groupId: GROUPS.NINJA.ID, cost: 200, currency: 'ninja_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ninja/ninja_base_key.png'
      backgroundColor: '#F44336'
      count: 1
      itemKeys: ['ninja_base_key']
  }
  ninja_base_chest: {
    type: 'pack', groupId: GROUPS.NINJA.ID, name: 'Daily Free Chests', cost: 0, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ninja/ninja_base_chest.png'
      backgroundColor: '#9C27B0'
      lockTime: ONE_DAY_SECONDS
      count: 2
      itemKeys: ['ninja_chest', 'ninja_base_chest']
  }
  ninja_name_color_base_7_days: {
    name: 'Name color (7d)'
    type: 'pack'
    groupId: GROUPS.NINJA.ID
    cost: 500
    currency: 'ninja_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ninja/ninja_name_color_base_7_days.png'
      backgroundColor: '#333'
      count: 1
      itemKeys: ['ninja_name_color_base_7_days']
  }
  ninja_name_color_premium_7_days: {
    name: 'Name color (premium, 7d)'
    type: 'pack'
    groupId: GROUPS.NINJA.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/ninja/ninja_name_color_premium_7_days.png'
      backgroundColor: '#eeeeee'
      count: 1
      itemKeys: ['ninja_name_color_premium_7_days']
  }

  # THE VIEWAGE
  tv_key: {
    name: '#TheViewage Premium Key', type: 'pack', groupId: GROUPS.THE_VIEWAGE.ID, cost: 200, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tv/tv_key.png'
      backgroundColor: '#2196F3'
      count: 1
      itemKeys: ['tv_key']
  }
  tv_base_key: {
    name: '#TheViewage Base Key', type: 'pack', groupId: GROUPS.THE_VIEWAGE.ID, cost: 200, currency: 'tv_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tv/tv_base_key.png'
      backgroundColor: '#F44336'
      count: 1
      itemKeys: ['tv_base_key']
  }
  tv_base_chest: {
    type: 'pack', groupId: GROUPS.THE_VIEWAGE.ID, name: 'Daily Free Chests', cost: 0, currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tv/tv_base_chest.png'
      backgroundColor: '#9C27B0'
      lockTime: ONE_DAY_SECONDS
      count: 2
      itemKeys: ['tv_chest', 'tv_base_chest']
  }
  tv_name_color_base_7_days: {
    name: 'Name color (7d)'
    type: 'pack'
    groupId: GROUPS.THE_VIEWAGE.ID
    cost: 500
    currency: 'tv_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tv/tv_name_color_base_7_days.png'
      backgroundColor: '#333'
      count: 1
      itemKeys: ['tv_name_color_base_7_days']
  }
  tv_name_color_premium_7_days: {
    name: 'Name color (premium, 7d)'
    type: 'pack'
    groupId: GROUPS.THE_VIEWAGE.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/tv/tv_name_color_premium_7_days.png'
      backgroundColor: '#eeeeee'
      count: 1
      itemKeys: ['tv_name_color_premium_7_days']
  }

  # CLASH ROYALE ENGLISH
  cr_en_pack_free: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN.ID
    name: 'Free Clash Royale Sticker Pack (1)'
    cost: 0
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_en_free.png'
      backgroundColor: '#9C27B0'
    }, DEFAULT_FREE_PACK_DATA
  }
  cr_en_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN.ID
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_en_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_en_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN.ID
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_en_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  cr_en_google_play_10: {
    type: 'general'
    name: '$10 Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_EN.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_en_visa_10: {
    type: 'general'
    name: '$10 Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_EN.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE SPANISH
  cr_es_pack_free: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_ES.ID
    name: 'Clash Royale Sticker Pack'
    cost: 200
    currency: 'cr_es_currency'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_es_free.png'
      backgroundColor: '#9C27B0'
    }, DEFAULT_3_PACK_DATA
  }
  cr_es_name_color_base_7_days: {
    name: 'Nombre de color (7d)'
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_ES.ID
    cost: 500
    currency: 'cr_es_currency'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr/cr_name_color_base_7_days.png'
      backgroundColor: '#333'
      count: 1
      itemKeys: ['cr_es_name_color_base_7_days']
  }
  cr_es_name_color_premium_7_days: {
    name: 'Nombre de color (prima, 7d)'
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_ES.ID
    cost: 200
    currency: 'fire'
    data:
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr/cr_name_color_premium_7_days.png'
      backgroundColor: '#eeeeee'
      count: 1
      itemKeys: ['cr_es_name_color_premium_7_days']
  }
  # cr_es_pack1: {
  #   type: 'pack'
  #   groupId: GROUPS.CLASH_ROYALE_ES.ID
  #   name: 'Pack de Stickers Clash Royale (1)'
  #   cost: 100 # 10c
  #   data: _.defaults {
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_es_1.png'
  #     backgroundColor: '#F44336'
  #   }, DEFAULT_1_PACK_DATA
  # }
  # cr_es_pack3: {
  #   type: 'pack'
  #   name: 'Pack de Stickers Clash Royale (3)'
  #   groupId: GROUPS.CLASH_ROYALE_ES.ID
  #   cost: 250 # 25c
  #   data: _.defaults {
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_es_3.png'
  #     backgroundColor: '#2196F3'
  #   }, DEFAULT_3_PACK_DATA
  # }
  cr_es_google_play_10: {
    type: 'general'
    name: '$10 USD Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_ES.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_es_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_ES.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE PORTUGUESE
  cr_pt_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PT.ID
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_pt_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_pt_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PT.ID
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_pt_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  cr_pt_google_play_10: {
    type: 'general'
    name: '30 BRL Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PT.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_pt_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PT.ID
    cost: 15000
    currency: 'fire'
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE POLISH
  cr_pl_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PL.ID
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_pl_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_pl_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PL.ID
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    currency: 'fire'
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/fam/packs/cr_pl_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  # cr_pl_google_play_10: {
  #   type: 'general'
  #   name: '30 BRL Google Play Gift Card'
  #   groupId: GROUPS.CLASH_ROYALE_PL.ID
  #   cost: 15000
  #   data: {
  #     backgroundImage: 'https://cdn.wtf/d/images/fam/products/google_play.png'
  #     backgroundColor: '#4CAF50'
  #   }
  # }
  cr_pl_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PL.ID
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/fam/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

module.exports = _.map products, (value, key) -> _.defaults {key}, value
# coffeelint: enable=max_line_length,cyclomatic_complexity
