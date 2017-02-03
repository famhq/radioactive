Promise = require 'bluebird'
google = require 'googleapis'
OAuth2 = google.auth.OAuth2
moment = require 'moment'
_ = require 'lodash'
cld = require 'cld'

Video = require '../models/video'
ImageService = require './image'
config = require '../config'


oauth2Client = new OAuth2(
  config.GOOGLE.CLIENT_ID
  config.GOOGLE.CLIENT_SECRET
  config.GOOGLE.REDIRECT_URL
)

# scopes = [
#   'https://www.googleapis.com/auth/drive'
#   'https://www.googleapis.com/auth/youtube'
# ]
# url = oauth2Client.generateAuthUrl {
#   access_type: 'offline'
#   scope: scopes
# }
# # austin@clay.io
# return console.log url
# if you need a new refresh_token, get a code (url above), put into var below
# and get token
# code = '4/gMfCZbMpsAfzRoE__lIrwtrnvaOT6H3CPzW7nvOU3-M'
# return oauth2Client.getToken code, (err, token) ->
#   console.log err, token

oauth2Client.setCredentials {refresh_token: config.GOOGLE.REFRESH_TOKEN}
youtube = google.youtube {
  version: 'v3',
  auth: oauth2Client
}

YOUTUBE_VIDEO_COUNT = 400
END_VIDEO_COUNT = 10
MIN_ENGLISH_PERCENT = 85
BLACKLISTED_WORDS = [
  'free', 'gem', 'hack', 'coins', 'chest', 'deutsch', 'german', '¡', 'pack',
  'indonesia', 'glitch'
]
blacklistedRegExp = new RegExp "#{BLACKLISTED_WORDS.join('|')}", 'ig'
# default weight = 1
channelWeights =
  'UC_F8DoJf9MZogEOU51TpTbQ': 2 # clash royale
  'UC3S6nIDGJ5OtpC-mbvFA8Ew': 2 # orange juice
  'UCqS6pRHyPYPZk1jrwakRuTg': 2 # M4SON
  'UCahcB0CpQjzUl2Voxd9hH0Q': 1.5 # phonecatss
  'UCxNMYToYIBPYV829BJcmUQg': 1.5 # chief pat
  'UCTqoYXL5p_aOdsgDWzxRBzQ': 1.5 # clash with ash
  'UC13Wn-IuMV4i78-bk3A7dzg': 1.5 # the rum ham
  'UCKGZr9bU_zuVJPbYdWvIW7g': 1.5 # spencer23
  'UCLAOdac7WmMXQKhOP-8lmrQ': 0.5 # Eclihpse


log10 = (num) ->
  num = parseInt num
  if num and not isNaN num
    Math.log(num) / Math.log(10)
  else 0

class VideoDisoveryService
  getYoutubeVideos: (pageToken, pageInt = 1) =>
    pages = Math.ceil(YOUTUBE_VIDEO_COUNT / 50)
    Promise.promisify(youtube.search.list) {
      part: 'snippet'
      q: 'clash royale'
      maxResults: 50
      pageToken
      # regionCode: 'US'
      relevanceLanguage: 'en-us'
      type: 'video'
      publishedAfter: moment().subtract(1, 'day').toISOString()
      videoEmbeddable: true
    }
    .then (results) =>
      videos = results.items
      if pageInt < pages and results.nextPageToken
        @getYoutubeVideos results.nextPageToken, pageInt + 1
        .then (moreVideos) ->
          return videos.concat moreVideos
      else
        videos

  getYoutubeVideosStats: (ids) =>
    Promise.promisify(youtube.videos.list) {
      part: 'statistics,snippet,contentDetails'
      id: _.take(ids, 50).join(',')
      maxResults: 50
    }
    .then (results) =>
      videos = results.items
      if ids.length > 50
        @getYoutubeVideosStats _.takeRight(ids, ids.length - 50)
        .then (moreVideos) ->
          return videos.concat moreVideos
      else
        videos

  discover: =>
    @getYoutubeVideos()
    .filter (item) ->
      title =  item.snippet.title
      description = item.snippet.description
      text = "#{title} #{description}"
      isEnglish = Promise.promisify(cld.detect) text, {
        # languageHint: 'ENGLISH'
      }
      .then (result) ->
        # if result.languages[0].name is 'ENGLISH' and title.indexOf('NASIB') isnt -1
        #   console.log result.languages
        return result.languages[0].name is 'ENGLISH' and
                result.languages[0].percent > MIN_ENGLISH_PERCENT
      .catch ->
        return false

      isBlacklisted = Promise.resolve title.match blacklistedRegExp

      Promise.all [
        isEnglish
        isBlacklisted
      ]
      .then ([isEnglish, isBlacklisted]) ->
        isEnglish and not isBlacklisted
    .then (videos) =>
      ids = _.map(videos, ({id}) -> id.videoId)
      @getYoutubeVideosStats ids
    .then (videos) =>
      sortedVideos = _.orderBy videos, @getScoreByVideo, 'desc'

      truncatedVideos = _.take sortedVideos, END_VIDEO_COUNT
    .map (video) =>
      console.log video.snippet.channelTitle, @getScoreByVideo video
      Video.create {
        title: video.snippet.title
        description: video.snippet.description
        duration: video.contentDetails.duration
        source: 'youtube'
        sourceId: video.id
        authorId: video.snippet.channelId
        authorName: video.snippet.channelTitle
        time: new Date(video.snippet.publishedAt)
      }
      .tap ({id, sourceId}) ->
        keyPrefix = "images/starfire/vt/#{id}"
        ImageService.getVideoPreview keyPrefix, sourceId
        .then (thumbnailImage) ->
          Video.updateById id, {thumbnailImage}

  getScoreByVideo: (item) ->
    {likeCount, dislikeCount, commentCount, viewCount} = item.statistics
    commentScore = log10(commentCount)
    viewCountScore = log10(commentCount)
    likeCountScore = log10(likeCount)
    likeDislikeScore = if likeCount / dislikeCount > 0.95 then 2 \
                       else if likeCount / dislikeCount < 0.7 then 0
                       else 1

    weight = channelWeights[item.snippet.channelId] or 1
    score =
      Math.pow(commentScore, 0.6) *
      Math.pow(viewCountScore, 0.4) *
      Math.pow(likeCountScore, 0.7) *
      Math.pow(likeDislikeScore, 2) *
      Math.pow(weight, 2)
    return score

module.exports = new VideoDisoveryService()

# module.exports.discover()
