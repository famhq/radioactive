_ = require 'lodash'
assertNoneMissing = require 'assert-none-missing'

env = process.env

# REDIS_PORT = if env.IS_STAGING is '1' then 6378 else 6379 # for cluster
REDIS_PORT = 6379
DEV_USE_HTTPS = process.env.DEV_USE_HTTPS and process.env.DEV_USE_HTTPS isnt '0'

config =
  LEGACY_CLASH_ROYALE_ID: '319a9065-e3dc-4d02-ad30-62047716a88f'
  DEFAULT_GAME_KEY: 'clash-royale'
  GROUPS:
    PLAY_HARD:
      ID: 'ad25e866-c187-44fc-bdb5-df9fcc4c6a42'
      APP_KEY: ''
    TEAM_QUESO:
      ID: '4e825b23-5bad-4f0a-9463-e41eee588a95'
      APP_KEY: 'teamqueso'
    NINJA:
      ID: 'c03872fa-6b0d-4bf7-93cd-9b8091a6894b'
      APP_KEY: 'ninja'
    STARFIRE:
      ID: '319a9065-e3dc-4d02-ad30-62047716a88f'
      APP_KEY: 'openfam'
    MAIN:
      ID: '319a9065-e3dc-4d02-ad30-62047716a88f'
      APP_KEY: 'openfam'
    ECLIHPSE:
      ID: '137ec250-0941-4d72-8074-b257e0966c17'
      APP_KEY: ''
    NICKATNYTE:
      ID: 'b8e3e948-6f9a-4f7d-a6ef-7b0b35f3a523'
      APP_KEY: 'nickatnyte'
    FERG:
      ID: '2a2c1d78-33e1-4d32-b483-83074935db2c'
      APP_KEY: ''
    THE_VIEWAGE:
      ID: '13673f46-fd1e-4768-8963-21cb4b2ee96e'
      APP_KEY: 'theviewage'
    CLASH_ROYALE_EN:
      ID: '73ed4af0-a2f2-4371-a893-1360d3989708'
      APP_KEY: ''
    CLASH_ROYALE_ES:
      ID: '4f26e51e-7f35-41dd-9f21-590c7bb9ce34'
      APP_KEY: 'clashroyalees'
    CLASH_ROYALE_PT:
      ID: '68acb51a-3e5a-466a-9e31-c93aacd5919e'
      APP_KEY: ''
    CLASH_ROYALE_PL:
      ID: '22e9db0b-45be-4c6d-86a5-434b38684db9'
      APP_KEY: ''
    FORTNITE_ES:
      ID: '308783ea-02d5-4d3a-8357-6efd369cf01d'
      APP_KEY: 'fortnitees'
  CLASH_ROYALE_TROPHIES_RECORD_ID: 'ed3b3643-039b-4a3f-9d44-0742b86e0a2c'
  CLASH_ROYALE_DONATIONS_RECORD_ID: '3b87da6c-7a2b-42c1-a59d-7354acaf80b0'
  CLASH_ROYALE_CLAN_CROWNS_RECORD_ID: 'aee6d338-2d6e-4b9a-af65-a48674bce3ef'
  CLASH_ROYALE_CLAN_DONATIONS_RECORD_ID: 'e3f646a8-d810-4df7-8cdd-ffaa1fb879e0'
  CLASH_ROYALE_CLAN_TROPHIES_RECORD_ID: '0135ddf8-7a24-4f40-b828-d43c39d6553c'
  MAIN_GROUP_ID: '73ed4af0-a2f2-4371-a893-1360d3989708' # TODO: remove?
  COMMUNITY_LANGUAGES: ['es', 'pt']
  DECK_TRACKED_GAME_TYPES: [
    'PvP', 'classicChallenge', 'grandChallenge', 'tournament', '2v2'
    # 'newCardChallenge'
  ]
  # also in fam
  DEFAULT_PERMISSIONS:
    readMessage: true
    sendMessage: true
    sendLink: true
    sendImage: true
    sendAddon: true
  DEFAULT_NOTIFICATIONS:
    chatMessage: true
    chatMention: true
  # also in fam
  LANGUAGES: [
    'en', 'es', 'it', 'fr', 'zh', 'ja', 'ko', 'de', 'pt', 'pl', 'ru'
    'id', 'tr', 'tl'
  ]
  # also in fam
  ITEM_LEVEL_REQUIREMENTS: [
    {level: 3, countRequired: 100}
    {level: 2, countRequired: 10}
    {level: 1, countRequired: 0}
  ]
  # also in fam TODO: shared config file
  XP_LEVEL_REQUIREMENTS: [
    {level: 1, xpRequired: 0}
    {level: 2, xpRequired: 20}
    {level: 3, xpRequired: 50}
    {level: 4, xpRequired: 100}
    {level: 5, xpRequired: 200}
    {level: 6, xpRequired: 500}
    {level: 7, xpRequired: 1000}
    {level: 8, xpRequired: 2000}
    {level: 9, xpRequired: 5000}
    {level: 10, xpRequired: 10000}
    {level: 11, xpRequired: 30000}
    {level: 12, xpRequired: 60000}
  ]
  NOTIFICATION_COLOR: '#fc373e'
  RARITY_XP:
    starter: 2
    common: 2
    rare: 10
    epic: 30
    legendary: 80
  EMPTY_UUID: '00000000-0000-0000-0000-000000000000'

  # also in fam
  BASE_NAME_COLORS: ['#2196F3', '#8BC34A', '#FFC107', '#f44336', '#673AB7']

  IS_POSTGRES: env.IS_POSTGRES or false

  VERBOSE: if env.VERBOSE then env.VERBOSE is '1' else true
  PORT: env.RADIOACTIVE_PORT or 50000
  ENV: env.DEBUG_ENV or env.NODE_ENV
  IS_STAGING: env.IS_STAGING is '1'
  JWT_ES256_PRIVATE_KEY: env.JWT_ES256_PRIVATE_KEY
  JWT_ES256_PUBLIC_KEY: env.JWT_ES256_PUBLIC_KEY
  JWT_ISSUER: 'exoid'
  DEV_USE_HTTPS: DEV_USE_HTTPS
  MAX_CPU: env.RADIOACTIVE_MAX_CPU or 1
  APN_CERT: env.RADIOACTIVE_APN_CERT
  APN_KEY: env.RADIOACTIVE_APN_KEY
  APN_PASSPHRASE: env.RADIOACTIVE_APN_PASSPHRASE
  GOOGLE_PRIVATE_KEY_JSON: env.GOOGLE_PRIVATE_KEY_JSON
  GOOGLE_API_KEY: env.GOOGLE_API_KEY
  GOOGLE_API_KEY_MYSTIC: env.GOOGLE_API_KEY_MYSTIC
  CARD_CODE_MAX_LENGTH: 9999999999
  PCG_SEED: env.RADIOACTIVE_PCG_SEED
  PT_UTC_OFFSET: -8
  IOS_BUNDLE_ID: 'com.clay.redtritium'
  DEALER_API_URL: env.DEALER_API_URL
  DEALER_SECRET: env.DEALER_SECRET
  CR_API_URL: env.CR_API_URL
  CR_API_SECRET: env.CR_API_SECRET
  RADIOACTIVE_API_URL: env.RADIOACTIVE_API_URL
  VAPID_SUBJECT: env.RADIOACTIVE_VAPID_SUBJECT
  VAPID_PUBLIC_KEY: env.RADIOACTIVE_VAPID_PUBLIC_KEY
  VAPID_PRIVATE_KEY: env.RADIOACTIVE_VAPID_PRIVATE_KEY
  STRIPE_SECRET_KEY: env.STRIPE_SECRET_KEY
  KIIP_API_KEY: env.KIIP_API_KEY
  KIIP_API_SECRET: env.KIIP_API_SECRET
  KIIP_MOMENT_ID: 'default' # TODO
  FYBER_APP_ID: env.FYBER_ANDROID_APP_ID
  FYBER_API_KEY: env.FYBER_ANDROID_API_KEY
  FYBER_SECURITY_TOKEN: env.FYBER_ANDROID_SECURITY_TOKEN
  IRONSOURCE_SECRET_KEY: env.IRONSOURCE_SECRET_KEY
  MAPPSTREET_PRIVATE_TOKEN: env.MAPPSTREET_PRIVATE_TOKEN
  ADSCEND_PUBLISHER_ID: env.ADSCEND_PUBLISHER_ID
  ADSCEND_SECRET_KEY: env.ADSCEND_SECRET_KEY
  NATIVE_SORT_OF_SECRET: env.NATIVE_SORT_OF_SECRET
  HONEYPOT_ACCESS_KEY: env.HONEYPOT_ACCESS_KEY
  CLASH_ROYALE_API_URL: 'https://api.clashroyale.com/v1'
  CLASH_ROYALE_API_KEY: env.CLASH_ROYALE_API_KEY
  FORTNITE_EMAIL: env.FORTNITE_EMAIL
  FORTNITE_PASSWORD: env.FORTNITE_PASSWORD
  FORTNITE_CLIENT_LAUNCHER_TOKEN: env.FORTNITE_CLIENT_LAUNCHER_TOKEN
  FORTNITE_CLIENT_TOKEN: env.FORTNITE_CLIENT_TOKEN
  GA_ID: env.RADIOACTIVE_GA_ID
  TWITCH:
    CLIENT_ID: env.TWITCH_CLIENT_ID
    CLIENT_SECRET: env.TWITCH_CLIENT_SECRET
    SECRET_KEY: env.TWITCH_SECRET_KEY
  GOOGLE:
    CLIENT_ID: env.GOOGLE_CLIENT_ID
    CLIENT_SECRET: env.GOOGLE_CLIENT_SECRET
    REFRESH_TOKEN: env.GOOGLE_REFRESH_TOKEN
    REDIRECT_URL: 'urn:ietf:wg:oauth:2.0:oob'
  GMAIL:
    USER: env.GMAIL_USER
    PASS: env.GMAIL_PASS
  RETHINK:
    DB: env.RETHINK_DB or 'radioactive'
    HOST: env.RETHINK_HOST or 'localhost'
  POSTGRES:
    HOST: env.POSTGRES_HOST or 'localhost'
    USER: env.POSTGRES_USER or 'postgres'
    PASS: env.POSTGRES_PASS or 'password'
    DB: env.POSTGRES_DB or 'clash_royale'
  REDIS:
    PREFIX: 'radioactive'
    PUB_SUB_PREFIX: 'radioactive_pub_sub'
    PORT: REDIS_PORT
    KUE_HOST: env.REDIS_KUE_HOST
    PUB_SUB_HOST: env.REDIS_PUB_SUB_HOST
    RADIOACTIVE_HOST: env.REDIS_RADIOACTIVE_HOST
    PERSISTENT_HOST: env.REDIS_PERSISTENT_HOST
  CDN_HOST: env.CDN_HOST
  SCYLLA:
    KEYSPACE: 'clash_royale'
    PORT: 9042
    CONTACT_POINTS: env.SCYLLA_CONTACT_POINTS.split(',')
  AWS:
    REGION: 'us-west-2'
    CDN_BUCKET: env.AWS_CDN_BUCKET
    ACCESS_KEY_ID: env.AWS_ACCESS_KEY_ID
    SECRET_ACCESS_KEY: env.AWS_SECRET_ACCESS_KEY
  ENVS:
    DEV: 'development'
    PROD: 'production'
    TEST: 'test'

assertNoneMissing config

module.exports = config
