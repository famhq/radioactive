Promise = require 'bluebird'
google = require 'googleapis'
OAuth2 = google.auth.OAuth2
moment = require 'moment'
_ = require 'lodash'
cld = require 'cld'

Video = require '../models/video'
Group = require '../models/group'
ImageService = require './image'
PushNotificationService = require './push_notification'
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

CHANNEL_IDS =
  "#{config.GROUPS.PLAY_HARD}": 'UC4IMfO_--bwBaNgWeoLxAgg'
  "#{config.GROUPS.ECLIHPSE}": 'UCLAOdac7WmMXQKhOP-8lmrQ'

class VideoDisoveryService
  updateGroupVideos: (groupId) ->
    hasSentPushNotification = false
    Promise.promisify(youtube.search.list) {
      part: 'snippet'
      channelId: CHANNEL_IDS[groupId]
      maxResults: 50
      type: 'video'
      order: 'date'
      videoEmbeddable: true
    }
    .then (response) =>
      ids = _.map(response.items, ({id}) -> id.videoId)
      @getYoutubeVideosInfo ids
    .then (videos) ->
      oldestVideo = _.minBy videos, (video) -> video.snippet.publishedAt
      minTime = new Date(oldestVideo.snippet.publishedAt)
      Promise.all [
        Video.getAllByGroupIdAndMinTime groupId, minTime
        Promise.resolve videos
        Group.getById groupId
      ]
    .then ([existingVideos, videos, group]) ->
      Promise.map videos, (video) ->
        exists = Boolean _.find existingVideos, {
          source: 'youtube'
          sourceId: video.id
        }
        isLive = video.snippet.liveBroadcastContent in ['live', 'upcoming']
        if not exists and not isLive
          if not hasSentPushNotification
            hasSentPushNotification = true
            PushNotificationService.sendToGroupTopic(
              group, {
                titleObj:
                  key: 'newVideo.title'
                textObj:
                  key: 'newVideo.text'
                  replacements:
                    groupName: group.name
                data:
                  path:
                    key: 'groupVideos'
                    params:
                      groupId: groupId
              }
            )

          Video.upsert {
            groupId: groupId
            title: video.snippet.title
            description: video.snippet.description
            duration: video.contentDetails.duration
            source: 'youtube'
            sourceId: video.id
            authorId: video.snippet.channelId
            authorName: video.snippet.channelTitle
            time: new Date(video.snippet.publishedAt)
          }
          .tap (video) ->
            keyPrefix = "images/starfire/vt/#{video.id}"
            ImageService.getYoutubePreview keyPrefix, video.sourceId
            .then (thumbnailImage) ->
              Video.upsert _.defaults {
                thumbnailImage: JSON.stringify thumbnailImage
              }, video

  getYoutubeVideosInfo: (ids) =>
    Promise.promisify(youtube.videos.list) {
      part: 'statistics,snippet,contentDetails'
      id: _.take(ids, 50).join(',')
      maxResults: 50
    }
    .then (results) =>
      videos = results.items
      if ids.length > 50
        @getYoutubeVideosInfo _.takeRight(ids, ids.length - 50)
        .then (moreVideos) ->
          return videos.concat moreVideos
      else
        videos


module.exports = new VideoDisoveryService()
