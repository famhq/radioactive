_ = require 'lodash'
config = require '../config'

# overlaps with language model in fam
class Language
  constructor: ->
    files = {
      strings: null
      cards: null
      addons: null
      paths: null
      languages: null
      pushNotifications: null
      backend: null
      fortnite: null
    }

    @files = _.mapValues files, (val, file) ->
      file = _.snakeCase file
      _.reduce config.LANGUAGES, (obj, lang) ->
        obj[lang] = try require "../lang/#{lang}/#{file}_#{lang}.json" \
                    catch e then null
        obj
      , {}

  getLanguageByCountry: (country) ->
    country = country?.toUpperCase()
    if country in [
      'AR', 'BO', 'CR', 'CU', 'DM', 'EC', 'SV', 'GQ', 'GT', 'HN', 'MX'
      'NI', 'PA', 'PE', 'ES', 'UY', 'VE'
    ]
      'es'
    else if country is 'IT'
      'it'
    else if country is 'BR'
      'pt'
    else if country is 'FR'
      'fr'
    else
      'en'

  get: (strKey, {replacements, file, language} = {}) =>
    file ?= 'backend'
    language ?= 'en'
    baseResponse = @files[file][language]?[strKey] or
                    @files[file]['en']?[strKey] or ''

    unless baseResponse
      console.log 'missing', file, strKey

    if typeof baseResponse is 'object'
      # some languages (czech) have many plural forms
      pluralityCount = replacements[baseResponse.pluralityCheck]
      baseResponse = baseResponse.plurality[pluralityCount] or
                      baseResponse.plurality.other or ''

    _.reduce replacements, (str, replace, key) ->
      find = ///{#{key}}///g
      str.replace find, replace
    , baseResponse


module.exports = new Language()
