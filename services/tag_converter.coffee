UINT32 = require('cuint').UINT32

class TagConverterService
  getTagFromHiLo: (hi, lo) ->
    idChars = '0289PYLQGRJCUV'
    hashtag = ''

    charCount = idChars.length

    id = UINT32(lo).shiftLeft(8).add UINT32(hi)
    while id > 0
      remainder = Math.floor(id % charCount)
      hashtag = idChars[remainder] + hashtag
      id = id.subtract UINT32(remainder)
      id = id.div UINT32(charCount), id
    return hashtag

  getHiLoFromTag: (hashtag) ->
    idChars = '0289PYLQGRJCUV'
    charCount = idChars.length
    id = 0
    i = 0
    hashtag.split('').forEach (char) ->
      charIndex = idChars.indexOf(char)
      id *= charCount
      id += charIndex
      i += charIndex

    hi = id % 256
    lo = (id - hi) >>> 8

    {hi, lo}

module.exports = new TagConverterService()
