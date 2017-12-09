# coffeelint: disable=max_line_length,cyclomatic_complexity
_ = require 'lodash'

config = require '../../config'

ONE_DAY_SECONDS = 3600 * 24

# https://itunes.apple.com/lookup?id=1150318642 (can also use &country=ca)

specialOffers = [
  {
    id: '697839e2-1084-4bcd-bd5c-fae5e5613c55'
    name: 'Arena of Valor'
    iOSPackage: 'com.ngame.allstar.eu'
    androidPackage: 'com.ngame.allstar.eu'
    # TODO
    backgroundImage: 'https://pbs.twimg.com/profile_banners/887561417259237377/1512487081/1500x500'
    backgroundColor: '#4c2b2e'
    textColor: '#ffffff'
    countryData: {} # [{installPayout, dailyPayout, days, minutesPerDay}]
    defaultData:
      installPayout: 100 # 10c
      dailyPayout: 50 # 5c
      days: 3
      minutesPerDay: 10
  }
  {
    id: '25d1d9e8-265c-42c0-bff3-2fc01c0e87a3'
    name: 'Coin Master'
    iOSPackage: 'com.mobile-softing.coinmaster'
    androidPackage: 'com.moonactive.coinmaster'
    # TODO
    backgroundImage: 'https://pbs.twimg.com/profile_banners/2965707675/1466583543/1500x500'
    backgroundColor: '#f5cc3e'
    textColor: '#000000'
    countryData: {} # [{installPayout, dailyPayout, days, minutesPerDay}]
    defaultData:
      installPayout: 100 # 10c
      dailyPayout: 50 # 5c
      days: 3
      minutesPerDay: 10
  }
]

module.exports = specialOffers
# coffeelint: enable=max_line_length,cyclomatic_complexity
