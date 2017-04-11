Canvas = require 'canvas'
Font = Canvas.Font
canvg = require 'canvg'
toHTML = require 'vdom-to-html'

s = require '../components/s'

rubikPath = __dirname + '/../fonts/Rubik-Bold.ttf'
# Canvas.registerFont rubikPath, {family: 'Rubik-Bold'}
rubikBold = new Font('Rubik-Bold', rubikPath)
rubikBold.addFace(rubikPath, 'bold')

rubikPath = __dirname + '/../fonts/Rubik-Medium.ttf'
# Canvas.registerFont rubikPath, {family: 'Rubik-Medium'}
rubikMedium = new Font('Rubik-Medium', rubikPath)
rubikMedium.addFace(rubikPath, 'medium')

module.exports = class Page
  render: =>
    @setup().then (props) =>
      @$$canvas ?= new Canvas(500, 100)
      ctx = @$$canvas.getContext('2d')
      ctx.addFont rubikBold
      ctx.addFont rubikMedium

      $svg = s 'svg',
        @renderHead props
        s(@$component, props)
      canvg @$$canvas, toHTML($svg), {ImageClass: Canvas.Image}
      @$$canvas.pngStream()
