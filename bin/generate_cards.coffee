#!/usr/bin/env coffee
_ = require 'lodash'
fs = require 'fs'
Promise = require 'bluebird'
Canvas = require 'canvas'
JsBarcode = require 'jsbarcode'
Rsvg = require('librsvg').Rsvg
stream = require 'stream'

User = require '../models/user'

BAR_WIDTH = 12
BAR_HEIGHT = 100
NUMBERS = _.range 1, 3#101

generateCode = (number) ->
  svg = new Canvas 1360, 100, 'svg'

  code = User.getCardCode {numericId: number}

  JsBarcode svg, code, {
    lineColor: '#fff'
    width: BAR_WIDTH
    height: BAR_HEIGHT
    displayValue: false
    margin: 0
    background: 'transparent'
  }
  svgString = svg.toBuffer().toString()
  svgString = svgString.replace /pt/ig, ''
  # width = parseInt(svgString.match(/width="([0-9]+)"/)[1])
  # width = svgString.match(/<path/ig).length * 1.2
  # width = svg.width
  # to properly force fixed width for code 128
  width = parseInt(_.last(svgString.match(/M ([0-9]+)/g)).replace('M ', '')) + BAR_WIDTH
  scale = 1360 / width
  """
  <g transform='scale(#{scale} 1)'>#{svgString}</g>
  """


Promise.each NUMBERS, (number) =>
  paddedNumber = _.padStart number, 4, '0'
  console.log paddedNumber
  path = "./resources/barcodes/MEMBER #{paddedNumber}.svg"
  Promise.all [
    generateCode number
    Promise.promisify(fs.readFile) path, 'utf8'
  ]
  .then ([codeSvg, numberSvg]) ->
    codeSvg = codeSvg.replace '<?xml version="1.0" encoding="UTF-8"?>', ''
    svg = """
    <?xml version="1.0" encoding="utf-8"?>
    <svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
       viewBox="0 0 100 1360" style="enable-background:new 0 0 100 1360;" xml:space="preserve">
       <g transform='translate(100 0) rotate(90)'>#{codeSvg}</g>
    </svg>
    """

    # pdf = new Rsvg()
    # bufferStream = new stream.PassThrough()
    # bufferStream.end svg
    # bufferStream.pipe pdf
    # pdf.on 'finish', ->
    #   fs.writeFile "./resources/generated_codes/#{number}.pdf", pdf.render({
    #     format: 'pdf'
    #     width: 100
    #     height: 1360
    #    }).data
    # return

    numberSvg = numberSvg.replace '<?xml version="1.0" encoding="UTF-8" standalone="no"?>', ''
    numberSvg = numberSvg.replace '#000', '#fff'
    codeSvg = codeSvg.replace '<?xml version="1.0" encoding="UTF-8"?>', ''
    svg = """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Generator: Adobe Illustrator 20.1.0, SVG Export Plug-In . SVG Version: 6.00 Build 0)  -->
    <svg version="1.1" id="Layer_1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" x="0px" y="0px"
       viewBox="0 0 350 200" style="enable-background:new 0 0 350 200;" xml:space="preserve">
    <style type="text/css">
      .st0{fill:#FFFFFF;}
    </style>
    <title>Card back</title>
    <desc>Created with Sketch.</desc>
    <g id="Page-1">
      <g id="Card-back">
        <g id="Card" transform="translate(0, 0)">
          <path id="Combined-Shape" d="M0,188c0,6.6,5.4,12,12,12h326c6.6,0,12-5.4,12-12V12c0-6.6-5.4-12-12-12H12C5.4,0,0,5.4,0,12V188z
             M177,58.5l24.4,42.3l-10.5,6.1l-14-8.1V58.5z M203.4,104.3L212,119l-17-9.8l0,0L203.4,104.3z M210,122.5h-48.9v-12.2l13.9-8
            L210,122.5L210,122.5z M157.1,122.5H140l17.1-9.9V122.5L157.1,122.5z M138,119l24.4-42.3l10.5,6.1v16L138,119L138,119z
             M164.5,73.2l8.5-14.7v19.7L164.5,73.2L164.5,73.2z"/>
          <path id="Circle" class="st0" d="M175,38c-34.2,0-62,27.8-62,62s27.8,62,62,62s62-27.8,62-62S209.2,38,175,38z M175,160
            c-33.1,0-60-26.9-60-60s26.9-60,60-60s60,26.9,60,60S208.1,160,175,160z"/>
          <g transform="translate(236, 175)">#{numberSvg}</g>
          <g transform="translate(#{BAR_HEIGHT + 16}, 32) rotate(90)">#{codeSvg}</g>

        </g>
      </g>
    </g>
    </svg>

    """
    pdf = new Rsvg()
    bufferStream = new stream.PassThrough()
    bufferStream.end svg
    bufferStream.pipe pdf
    pdf.on 'finish', ->
      fs.writeFile "./resources/generated_backs/card_#{number}.pdf", pdf.render({
        format: 'pdf'
        width: 350
        height: 200
       }).data

    fs.writeFile "./resources/generated_backs/card_#{number}.svg", svg, 'utf8'
