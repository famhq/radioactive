# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

GROUPS =
  PLAY_HARD: 'ad25e866-c187-44fc-bdb5-df9fcc4c6a42'
  CLASH_ROYALE_EN: '73ed4af0-a2f2-4371-a893-1360d3989708'
  CLASH_ROYALE_ES: '4f26e51e-7f35-41dd-9f21-590c7bb9ce34'
  CLASH_ROYALE_PT: '68acb51a-3e5a-466a-9e31-c93aacd5919e'
  CLASH_ROYALE_PL: '22e9db0b-45be-4c6d-86a5-434b38684db9'
  LEGACY: config.CLASH_ROYALE_ID

items =
  ph: {name: 'PlayHard', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_bruno: {name: 'Bruno', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_huum: {name: 'Huum', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_surpreso: {name: 'Surpreso', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_feliz: {name: 'Feliz', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_bora: {name: 'Bora', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_assustadao: {name: 'Assustadao', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_aleluia: {name: 'Aleluia', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_tenso: {name: 'Tenso', groupId: GROUPS.PLAY_HARD, rarity: 'common'}
  ph_hmm: {name: 'Hmm', groupId: GROUPS.PLAY_HARD, rarity: 'rare'}
  ph_uau: {name: 'Uau', groupId: GROUPS.PLAY_HARD, rarity: 'rare'}
  ph_love: {name: 'Love', groupId: GROUPS.PLAY_HARD, rarity: 'rare'}
  ph_voa: {name: 'Voa', groupId: GROUPS.PLAY_HARD, rarity: 'epic'}
  ph_god: {name: 'God', groupId: GROUPS.PLAY_HARD, rarity: 'legendary'}

  cr_en_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
  cr_en_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
  cr_en_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
  cr_en_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic'}
  cr_en_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare'}
  cr_en_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
  cr_en_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
  cr_en_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}

  cr_es_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}
  cr_es_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}
  cr_es_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}
  cr_es_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'epic'}
  cr_es_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'rare'}
  cr_es_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}
  cr_es_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}
  cr_es_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_ES, rarity: 'common'}

  cr_pt_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}
  cr_pt_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}
  cr_pt_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}
  cr_pt_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'epic'}
  cr_pt_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'rare'}
  cr_pt_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}
  cr_pt_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}
  cr_pt_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PT, rarity: 'common'}

  cr_pl_starfire: {name: 'Starfire Logo', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}
  cr_pl_angry: {name: 'CR Angry', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}
  cr_pl_crying: {name: 'CR Crying', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}
  cr_pl_laughing: {name: 'CR Laughing', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'epic'}
  cr_pl_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'rare'}
  cr_pl_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}
  cr_pl_thumb: {name: 'CR Thumb', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}
  cr_pl_trophy: {name: 'CR Trophy', groupId: GROUPS.CLASH_ROYALE_PL, rarity: 'common'}

  # legacy items earned before 11/21
  sf_logo: {name: 'Starfire Logo', groupId: GROUPS.LEGACY, rarity: 'common'}
  cr_angry: {name: 'CR Angry', groupId: GROUPS.LEGACY, rarity: 'common'}
  cr_crying: {name: 'CR Crying', groupId: GROUPS.LEGACY, rarity: 'common'}
  cr_laughing: {name: 'CR Laughing', groupId: GROUPS.LEGACY, rarity: 'epic'}
  cr_shop_goblin: {name: 'CR Shop Goblin', groupId: GROUPS.LEGACY, rarity: 'rare'}
  cr_thumbs_up: {name: 'CR Thumbs Up', groupId: GROUPS.LEGACY, rarity: 'common'}
  cr_thumb: {name: 'CR Thumb', groupId: GROUPS.LEGACY, rarity: 'common'}
  cr_trophy: {name: 'CR Trophy', groupId: GROUPS.LEGACY, rarity: 'common'}

module.exports = _.map items, (value, key) -> _.defaults {key}, value

# cr_barbarian: {name: 'CR Barbarian', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic'}
# cr_blue_king: {name: 'CR Blue King', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
# cr_epic_chest: {name: 'CR Epic Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'epic'}
# cr_giant_chest: {name: 'CR Giant Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare'}
# cr_goblin: {name: 'CR Goblin', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare'}
# cr_gold_chest: {name: 'CR Gold Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
# cr_knight: {name: 'CR Knight', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare'}
# cr_magical_chest: {name: 'CR Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'rare'}
# cr_red_king: {name: 'CR Red King', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
# cr_silver_chest: {name: 'CR Silver chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'common'}
# cr_smc: {name: 'CR Super Magical Chest', groupId: GROUPS.CLASH_ROYALE_EN, rarity: 'legendary'}

# coffeelint: enable=max_line_length,cyclomatic_complexity
