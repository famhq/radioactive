_ = require 'lodash'
fs = require 'fs'

Component = require '../'
s = require '../s'

module.exports = class ChestCycle extends Component
  getHeight: -> 100

  render: ({images, player} = {}) ->
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
        width: '360'
        height: '447'
        fill: '#1a1a1a'
        rx: '10'
      }
      s 'text', {
        fill: '#FFF'
        'font-family': 'Rubik-Medium, Rubik'
        'font-size': '14'
        'font-weight': '400'
      },
        s 'tspan', {
          x: '73.971'
          y: '29'
        }, 'These are my upcoming chests!'

      s 'g', {
        transform: 'translate(16 230)'
      },
        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Regular, Rubik'
          'font-size': '12'
        },
          s 'tspan', {
            x: '11.56'
            y: '116'
          }, 'Super Magical'

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Regular, Rubik'
          'font-size': '12'
        },
          s 'tspan', {
            x: '135.27'
            y: '116'
          }, 'Legendary'

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Regular, Rubik'
          'font-size': '12'
        },
          s 'tspan', {
            x: '266.084'
            y: '116'
          }, 'Epic'

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Medium, Rubik'
          'font-size': '14'
          'font-weight': '400'
        },
          s 'tspan', {
            x: '33.266'
            y: '138'
          }, " +#{player.data.chestCycle.countUntil.superMagical + 1}"

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Medium, Rubik'
          'font-size': '14'
          'font-weight': '400'
        },
          s 'tspan', {
            x: '148.407'
            y: '138'
          }, " +#{player.data.chestCycle.countUntil.legendary + 1}"

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Medium, Rubik'
          'font-size': '14'
          'font-weight': '400'
        },
          s 'tspan', {
            x: '260.609'
            y: '138'
          }, " +#{player.data.chestCycle.countUntil.epic + 1}"

        s 'image', {
          width: '101'
          height: '101'
          'xlink:href': "data:image/png;base64,#{images.superMagicalChest}"
        }
        s 'image', {
          width: '101'
          height: '101'
          'xlink:href': "data:image/png;base64,#{images.legendaryChest}"
          x: '114'
        }
        s 'image', {
          width: '101'
          height: '101'
          'xlink:href': "data:image/png;base64,#{images.epicChest}"
          x: '227'
        }

      s 'g', {
        transform: 'translate(130 52)'
      },
        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Regular, Rubik'
          'font-size': '12'
        },
          s 'tspan', {
            x: '29.874'
            y: '116'
          }, _.startCase player.data.chestCycle.chests[0]

        s 'text', {
          fill: '#FFF'
          'font-family': 'Rubik-Medium, Rubik'
          'font-size': '14'
          'font-weight': '400'
        },
          s 'tspan', {
            x: '34.47'
            y: '138'
          }, 'Next'

        s 'image', {
          width: '101'
          height: '101'
          'xlink:href': "data:image/png;base64,#{images.nextChest}"
        }

      s 'path', {
        fill: '#FFF'
        'fill-opacity': '.06'
        d: 'M8 213h344v1H8z'
      }
      s 'image', {
        width: '130'
        height: '32'
        x: '116'
        y: '399'
        'xlink:href': "data:image/png;base64,#{images.poweredBy}"
      }

    # coffeelint: enable=max_line_length,cyclomatic_complexity
