Canvas = require 'canvas'
canvg = require 'canvg'
toHTML = require 'vdom-to-html'

s = require '../components/s'

module.exports = class Page
  render: =>
    @setup().then (props) =>
      rubikPath = '/home/austin/dev/pulsar/resources/fonts/Rubik-Regular.ttf'
      # Canvas.registerFont rubikPath, {family: 'Rubik-Regular'}
      @$$canvas ?= new Canvas(500, 100)
      $svg = s 'svg',
        @renderHead props
        s(@$component, props)
      canvg @$$canvas, toHTML($svg), {ImageClass: Canvas.Image}
      @$$canvas.pngStream()
