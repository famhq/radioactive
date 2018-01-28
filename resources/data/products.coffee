# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

ONE_DAY_SECONDS = 3600 * 24
GROUPS =
  PLAY_HARD: 'ad25e866-c187-44fc-bdb5-df9fcc4c6a42'
  CLASH_ROYALE_EN: '73ed4af0-a2f2-4371-a893-1360d3989708'
  CLASH_ROYALE_ES: '4f26e51e-7f35-41dd-9f21-590c7bb9ce34'
  CLASH_ROYALE_PT: '68acb51a-3e5a-466a-9e31-c93aacd5919e'
  CLASH_ROYALE_PL: '22e9db0b-45be-4c6d-86a5-434b38684db9'

DEFAULT_FREE_PACK_DATA =
  lockTime: ONE_DAY_SECONDS
  count: 1
  odds: [
    {rarity: 'common', odds: 0.8}
    {rarity: 'rare', odds: 0.13}
    {rarity: 'epic', odds: 0.05}
    {rarity: 'legendary', odds: 0.02}
  ]
DEFAULT_1_PACK_DATA =
  count: 1
  odds: [
    {rarity: 'common', odds: 0.8}
    {rarity: 'rare', odds: 0.13}
    {rarity: 'epic', odds: 0.05}
    {rarity: 'legendary', odds: 0.02}
  ]
DEFAULT_3_PACK_DATA =
  count: 3
  odds: [
    {rarity: 'common', odds: 0.8}
    {rarity: 'rare', odds: 0.13}
    {rarity: 'epic', odds: 0.05}
    {rarity: 'legendary', odds: 0.02}
  ]

products =
  # ph_shout_out_raffle: {
  #   type: 'raffle'
  #   groupId: GROUPS.PLAY_HARD
  #   name: 'PlayHard Raffle Ticket'
  #   cost: 50 # 5c
  #   data:
  #     backgroundImage: 'https://cdn.wtf/d/images/starfire/products/ph_shout_out_raffle.png'
  #     backgroundColor: '#ff7f00'
  #     info: '1 raffle ticket. On Feburary 2nd, 1 ticket will be selected at random
  #           and the winning user will get a shoutout in Bruno\'s video on the 3rd'
  # }
  ph_pack1: {
    type: 'pack'
    groupId: GROUPS.PLAY_HARD
    name: 'PlayHard Sticker Pack (1)'
    cost: 100 # 10c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/ph_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  ph_pack3: {
    type: 'pack'
    groupId: GROUPS.PLAY_HARD
    name: 'PlayHard Sticker Pack (3)'
    cost: 250 # 25c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/ph_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  ph_google_play_30: {
    name: '30 BRL Google Play'
    type: 'general'
    groupId: GROUPS.PLAY_HARD
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  ph_visa_10: {
    name: '$10 USD Visa Gift Card'
    type: 'general'
    groupId: GROUPS.PLAY_HARD
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }
  # ph_send_message: {
  #   name: 'Envie uma mensagem para Bruno'
  #   type: 'general'
  #   groupId: GROUPS.PLAY_HARD
  #   cost: 1000
  # }

  # CLASH ROYALE ENGLISH
  cr_en_pack_free: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN
    name: 'Free Clash Royale Sticker Pack (1)'
    cost: 0
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_en_free.png'
      backgroundColor: '#9C27B0'
    }, DEFAULT_FREE_PACK_DATA
  }
  cr_en_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_en_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_en_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_EN
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_en_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  cr_en_google_play_10: {
    type: 'general'
    name: '$10 Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_EN
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_en_visa_10: {
    type: 'general'
    name: '$10 Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_EN
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE SPANISH
  cr_es_pack_free: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_ES
    name: 'Gratis Pack de Stickers Clash Royale (1)'
    cost: 0
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_es_free.png'
      backgroundColor: '#9C27B0'
    }, DEFAULT_FREE_PACK_DATA
  }
  cr_es_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_ES
    name: 'Pack de Stickers Clash Royale (1)'
    cost: 100 # 10c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_es_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_es_pack3: {
    type: 'pack'
    name: 'Pack de Stickers Clash Royale (3)'
    groupId: GROUPS.CLASH_ROYALE_ES
    cost: 250 # 25c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_es_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  cr_es_google_play_10: {
    type: 'general'
    name: '$10 USD Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_ES
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_es_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_ES
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE PORTUGUESE
  cr_pt_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PT
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_pt_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_pt_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PT
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_pt_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  cr_pt_google_play_10: {
    type: 'general'
    name: '30 BRL Google Play Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PT
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/google_play.png'
      backgroundColor: '#4CAF50'
    }
  }
  cr_pt_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PT
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

  # CLASH ROYALE POLISH
  cr_pl_pack1: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PL
    name: 'Clash Royale Sticker Pack (1)'
    cost: 100 # 10c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_pl_1.png'
      backgroundColor: '#F44336'
    }, DEFAULT_1_PACK_DATA
  }
  cr_pl_pack3: {
    type: 'pack'
    groupId: GROUPS.CLASH_ROYALE_PL
    name: 'Clash Royale Sticker Pack (3)'
    cost: 250 # 25c
    data: _.defaults {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/packs/cr_pl_3.png'
      backgroundColor: '#2196F3'
    }, DEFAULT_3_PACK_DATA
  }
  # cr_pl_google_play_10: {
  #   type: 'general'
  #   name: '30 BRL Google Play Gift Card'
  #   groupId: GROUPS.CLASH_ROYALE_PL
  #   cost: 15000
  #   data: {
  #     backgroundImage: 'https://cdn.wtf/d/images/starfire/products/google_play.png'
  #     backgroundColor: '#4CAF50'
  #   }
  # }
  cr_pl_visa_10: {
    type: 'general'
    name: '$10 USD Visa Gift Card'
    groupId: GROUPS.CLASH_ROYALE_PL
    cost: 15000
    data: {
      backgroundImage: 'https://cdn.wtf/d/images/starfire/products/visa.png'
      backgroundColor: '#FFC107'
    }
  }

module.exports = _.map products, (value, key) -> _.defaults {key}, value
# coffeelint: enable=max_line_length,cyclomatic_complexity
