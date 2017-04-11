_ = require 'lodash'
fs = require 'fs'

Component = require '../'
s = require '../s'

module.exports = class ForumSig extends Component
  getHeight: -> 100

  render: ({player} = {}) ->
    # coffeelint: disable=max_line_length,cyclomatic_complexity
    s 'g', {
      fill: 'none'
      'fill-rule': 'evenodd'
    },
      s 'rect', {
        width: '500'
        height: '100'
        fill: '#000'
        rx: '10'
      }
      s 'rect', {
        width: '496'
        height: '94'
        x: '2'
        y: '2'
        # fill: '#FA464E'
        fill: 'url(#backgroundImage)'
        rx: '8'
      }
      s 'rect', {
        width: '66'
        height: '56'
        transform: 'translate(12, 20)'
        fill: 'url(#clanBadgeImage)'
      }
      s 'rect', {
        width: '66'
        height: '88'
        transform: 'translate(425, 4)'
        fill: 'url(#favoriteCardImage)'
      }
      s 'text', {
        fill: '#000'
        'font-family': 'Rubik-Bold, Rubik'
        'font-size': '24'
        'font-weight': 'bold'
        transform: 'translate(91 22)'
      },
        s 'tspan', {
          x: '0'
          y: '24'
        },
          player?.data?.name?.toUpperCase()

      s 'text', {
        fill: '#000'
        'font-family': 'Rubik-Bold, Rubik'
        'font-size': '24'
        'font-weight': 'bold'
        transform: 'translate(91 22)'
      },
        s 'tspan', {
          x: '0'
          y: '23'
        },
          player?.data?.name?.toUpperCase()

      s 'text', {
        fill: '#FFF'
        stroke: '#000'
        'font-family': 'Rubik-Bold, Rubik'
        'font-size': '24'
        'font-weight': 'bold'
        transform: 'translate(91 22)'
      },
        s 'tspan', {
          x: '0'
          y: '22'
        },
          player?.data?.name?.toUpperCase()

      s 'text', {
        fill: '#FFF'
        'font-family': 'Rubik-Medium, Rubik'
        'font-size': '14'
        'font-weight': '400'
        transform: 'translate(91 22)'
      },
        s 'tspan', {
          x: '0'
          y: '49'
        },
          '#' + player?.data?.clan?.tag
          ' · '
          player?.data?.clan?.name


    # coffeelint: enable=max_line_length,cyclomatic_complexity
