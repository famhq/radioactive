_ = require 'lodash'
fs = require 'fs'

Component = require '../'
s = require '../s'

module.exports = class ForumSig extends Component
  getHeight: -> 100

  render: ({player, images} = {}) ->
    playerName = player?.data?.name?.toUpperCase()
                .replace(/&/g, '&amp;')
                .replace(/</g, '&lt;')
                .replace(/>/g, '&gt;')
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
      s 'image', {
        width: '500'
        height: '100'
        # x: '0'
        # y: '2'
        # fill: '#FA464E'
        'xlink:href': "data:image/png;base64,#{images.background}"
        rx: '8'
      }
      s 'image', {
        width: '66'
        height: '56'
        transform: 'translate(12, 20)'
        'xlink:href': "data:image/png;base64,#{images.clanBadge}"
      }
      s 'image', {
        width: '66'
        height: '88'
        transform: 'translate(425, 4)'
        'xlink:href': "data:image/png;base64,#{images.card}"
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
          playerName

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
          playerName

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
          playerName

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
