# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

ONE_DAY_SECONDS = 3600 * 24

# https://itunes.apple.com/lookup?id=1150318642 (can also use &country=ca)

specialOffers = [
  # {
  #   id: '697839e2-1084-4bcd-bd5c-fae5e5613c55'
  #   name: 'Arena of Valor'
  #   iOSPackage: 'com.ngame.allstar.eu'
  #   androidPackage: 'com.ngame.allstar.eu'
  #   # TODO
  #   backgroundImage: 'https://pbs.twimg.com/profile_banners/887561417259237377/1512487081/1500x500'
  #   backgroundColor: '#4c2b2e'
  #   textColor: '#ffffff'
  #   countryData: {} # [{installPayout, dailyPayout, days, minutesPerDay}]
  #   defaultData:
  #     installPayout: 100 # 10c
  #     dailyPayout: 50 # 5c
  #     days: 3
  #     minutesPerDay: 10
  # }
  {
    id: '5762a7e3-0907-4c42-90dc-b73435ad52f2'
    name: 'Final Fantasy XV: A New Empire'
    iOSPackage: 'com.mobile-softing.coinmaster'
    androidPackage: 'com.epicactiononline.ffxv.ane'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/com_epicactiononline_ffxv_ane.jpg'
    backgroundColor: '#35b3c8'
    textColor: '#000000'
    countryData:
      us:
        installPayout: 60 # 6c
        dailyPayout: 180 # 18c
      # ca:
      #   installPayout: 60 # 6c
      #   dailyPayout: 180 # 18c
      kr:
        installPayout: 60 # 6c
        dailyPayout: 180 # 18c
      jp:
        installPayout: 60 # 6c
        dailyPayout: 180 # 18c
      br:
        installPayout: 3 # .3c
        dailyPayout: 40 # 4c
    defaultData:
      installPayout: 0 # 6c
      dailyPayout: 0 # 15c
      days: 3
      minutesPerDay: 30
      priority: 10
      trackUrl: 'https://control.kochava.com/v1/cpi/click?campaign_id=koniso-android-ybve1w8d1a21f1f1b88&network_id=7298&site_id=1&device_id={deviceId}'
  }
  {
    id: 'fdda171b-1438-4ae2-8116-f8c930bda5d8'
    name: 'Freestreet'
    iOSPackage: ''
    androidPackage: 'mappstreet.freestreet'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_freestreet.jpg'
    backgroundColor: '#7a2cc3'
    textColor: '#ffffff'
    countryData:
      us: {sourceId: 5366569}
      pl: {sourceId: 5366482}
      es: {sourceId: 5366518}
      pe: {sourceId: 5366476}
      it: {sourceId: 5366362}
      pr: {sourceId: 5546397}
      pt: {sourceId: 5366485}
      mx: {sourceId: 5366422}
      jp: {sourceId: 5366368}
      gt: {sourceId: 5366329}
      de: {sourceId: 5366320}
      fr: {sourceId: 5366314}
      ve: {sourceId: 5366578}
      ru: {sourceId: 5366494}
      tr: {sourceId: 5366551}
      pa: {sourceId: 5366467}
      kr: {sourceId: 5366380}
      sv: {sourceId: 5366302}
      cr: {sourceId: 5366275}
      ht: {sourceId: 5366335}
      cl: {sourceId: 5537121}
      bo: {sourceId: 5537070}
      ar: {sourceId: 5537022}
      ec: {sourceId: 5366569}
      co: {sourceId: 5366272}
      br: {sourceId: 5366248}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5546538 # rest of world
  }
  {
    id: '31a60f70-d019-48e8-958f-ecb933b3f76d'
    name: 'Sokoban'
    iOSPackage: ''
    androidPackage: 'mappstreet.sokoban'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_sokoban.jpg'
    backgroundColor: '#8c8270'
    textColor: '#ffffff'
    countryData:
      us: {sourceId: 5537640}
      pl: {sourceId: 5537484}
      es: {sourceId: 5537565}
      pe: {sourceId: 5537475}
      it: {sourceId: 5537295}
      pr: {sourceId: 5537490}
      pt: {sourceId: 5537487}
      mx: {sourceId: 5537388}
      jp: {sourceId: 5537301}
      gt: {sourceId: 5537253}
      de: {sourceId: 5537229}
      fr: {sourceId: 5537208}
      ve: {sourceId: 5537655}
      ru: {sourceId: 5537502}
      tr: {sourceId: 5537616}
      pa: {sourceId: 5537466}
      kr: {sourceId: 5537316}
      sv: {sourceId: 5537181}
      cr: {sourceId: 5537145}
      ht: {sourceId: 5537265}
      cl: {sourceId: 5537121}
      co: {sourceId: 5537133}
      bo: {sourceId: 5537070}
      ar: {sourceId: 5537022}
      ec: {sourceId: 5537175}
      br: {sourceId: 5537082}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5537739 # rest of world
  }
  {
    id: '0a8181db-0d49-48d1-bc7b-6badeaec630c'
    name: 'Mahjong Solitaire'
    iOSPackage: ''
    androidPackage: 'mappstreet.mohjong_solitaire'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_mohjong_solitaire.jpg'
    backgroundColor: '#f9e3da'
    textColor: '#000000'
    countryData:
      us: {sourceId: 5536893}
      pl: {sourceId: 5536737}
      es: {sourceId: 5536818}
      pe: {sourceId: 5536728}
      it: {sourceId: 5536548}
      pr: {sourceId: 5536743}
      pt: {sourceId: 5536740}
      mx: {sourceId: 5536641}
      jp: {sourceId: 5536554}
      gt: {sourceId: 5536506}
      de: {sourceId: 5536482}
      fr: {sourceId: 5536461}
      ve: {sourceId: 5536908}
      ru: {sourceId: 5536755}
      tr: {sourceId: 5536869}
      pa: {sourceId: 5536719}
      kr: {sourceId: 5536569}
      sv: {sourceId: 5536461}
      cr: {sourceId: 5536398}
      ht: {sourceId: 5536518}
      cl: {sourceId: 5536374}
      co: {sourceId: 5536386}
      bo: {sourceId: 5536323}
      ar: {sourceId: 5536275}
      ec: {sourceId: 5536428}
      br: {sourceId: 5536335}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5536992 # rest of world
  }
  {
    id: '215592c5-65e3-48bb-81be-31bfad7daf04'
    name: 'Silent Manager'
    iOSPackage: ''
    androidPackage: 'mappstreet.silentmanager'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_silentmanager.jpg'
    backgroundColor: '#008c6d'
    textColor: '#ffffff'
    countryData:
      us: {sourceId: 5364505}
      pl: {sourceId: 5364418}
      es: {sourceId: 5364454}
      pe: {sourceId: 5364412}
      it: {sourceId: 5364298}
      pr: {sourceId: 5498791}
      pt: {sourceId: 5364421}
      mx: {sourceId: 5364358}
      jp: {sourceId: 5364304}
      gt: {sourceId: 5364265}
      de: {sourceId: 5364256}
      fr: {sourceId: 5364250}
      ve: {sourceId: 5364514}
      ru: {sourceId: 5364430}
      tr: {sourceId: 5364487}
      pa: {sourceId: 5364403}
      kr: {sourceId: 5364316}
      sv: {sourceId: 5364238}
      cr: {sourceId: 5364211}
      ht: {sourceId: 5364271}
      cl: {sourceId: 5364205}
      co: {sourceId: 5364208}
      bo: {sourceId: 5364175}
      ar: {sourceId: 5364232}
      ec: {sourceId: 5536428}
      br: {sourceId: 5364184}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5498929 # rest of world
  }
  {
    id: '69896a8b-1157-479d-be32-a453d82731cf'
    name: 'Horoscope'
    iOSPackage: ''
    androidPackage: 'mappstreet.horoscope'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_horoscope.jpg'
    backgroundColor: '#240046'
    textColor: '#ffffff'
    countryData:
      us: {sourceId: 5361611}
      pl: {sourceId: 5361524}
      es: {sourceId: 5361560}
      pe: {sourceId: 5361518}
      it: {sourceId: 5361404}
      pr: {sourceId: 5498404}
      pt: {sourceId: 5361527}
      mx: {sourceId: 5361464}
      jp: {sourceId: 5361410}
      gt: {sourceId: 5361371}
      de: {sourceId: 5361362}
      fr: {sourceId: 5361356}
      ve: {sourceId: 5361620}
      ru: {sourceId: 5361536}
      tr: {sourceId: 5361593}
      pa: {sourceId: 5361509}
      kr: {sourceId: 5361422}
      sv: {sourceId: 5361344}
      cr: {sourceId: 5361317}
      ht: {sourceId: 5361377}
      cl: {sourceId: 5361311}
      co: {sourceId: 5361314}
      bo: {sourceId: 5361281}
      ar: {sourceId: 5361242}
      ec: {sourceId: 5361338}
      br: {sourceId: 5361290}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5498545 # rest of world
  }
  {
    id: '5e7ec3d1-4c88-4bb2-adf7-97032c52be09'
    name: 'Future SMS'
    iOSPackage: ''
    androidPackage: 'mappstreet.futuresms'
    backgroundImage: 'https://cdn.wtf/d/images/fam/offers/mappstreet_futuresms.jpg'
    backgroundColor: '#9cf49c'
    textColor: '#000000'
    countryData:
      us: {sourceId: 5357024}
      pl: {sourceId: 5356995}
      es: {sourceId: 5357007}
      pe: {sourceId: 5356993}
      it: {sourceId: 5356955}
      pr: {sourceId: 5498068}
      pt: {sourceId: 5356996}
      mx: {sourceId: 5356975}
      jp: {sourceId: 5356957}
      gt: {sourceId: 5356944}
      de: {sourceId: 5356941}
      fr: {sourceId: 5356939}
      ve: {sourceId: 5357027}
      ru: {sourceId: 5356999}
      tr: {sourceId: 5357018}
      pa: {sourceId: 5356990}
      kr: {sourceId: 5356961}
      sv: {sourceId: 5356935}
      cr: {sourceId: 5356926}
      ht: {sourceId: 5356946}
      cl: {sourceId: 5356924}
      co: {sourceId: 5356925}
      bo: {sourceId: 5356914}
      ar: {sourceId: 5356901}
      ec: {sourceId: 5356933}
      br: {sourceId: 5356917}
    defaultData:
      installPayout: 2 # 0.2c
      dailyPayout: 30 # 3c
      days: 1
      minutesPerDay: 6
      sourceType: 'mappstreet'
      sourceId: 5498209 # rest of world
  }
]

module.exports = specialOffers
# coffeelint: enable=max_line_length,cyclomatic_complexity
