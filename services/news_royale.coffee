Promise = require 'bluebird'
request = require 'request-promise'
cheerio = require 'cheerio'
moment = require 'moment'
turndown = new require('turndown')()
_ = require 'lodash'

Thread = require '../models/thread'
cknex = require '../services/cknex'
config = require '../config'

CLASH_ROYALE_ES_GROUP_ID = '4f26e51e-7f35-41dd-9f21-590c7bb9ce34'
CLASH_ROYALE_ES_USER_ID = 'c38537b8-4831-4c58-b230-08df67cdfcd2'

# FIXME FIXME: grab thumbnail from post and use as attachment

class NewsRoyaleService
  scrape: ->
    console.log 'scrape'
    request 'https://inbox.clashroyale.com/es/news.html'
    .then (response) ->
      # console.log response
      $ = cheerio.load response
      posts = $('article').not('.hidden').map (i, el) ->
        thumbnail = $(el).find('source').attr('data-srcset')
        thumbnail = thumbnail?.split(' ')?[0]
        {
          id: $(el).attr('data-post-id')
          url: $(el).find('a').attr('href')
          timestamp: $(el).find('.article-date').attr('data-timestamp')
          thumbnail: thumbnail
        }
      .get()

      posts = _.filter posts, ({id, url}) -> id and url

      Thread.getAll {
        groupId: CLASH_ROYALE_ES_GROUP_ID
        category: 'news'
        sort: 'new'
        # maxTimeUuid: cknex.getTimeUuid new Date(lastPost.timestamp)
        limit: 10
      }
      .then (existingThreads) ->
        Promise.map posts, (post) ->
          exists = Boolean _.find existingThreads, (thread) ->
            thread.data?.extras?.newsRoyalePostId is post.id
          unless exists
            urlParts = post.url.split('/news/')
            pathParts = urlParts[1].split('?')
            path = encodeURIComponent pathParts[0]
            qs = pathParts[1]
            url = "#{urlParts[0]}/news/#{path}?#{qs}"
            request url
            .catch (err) ->
              console.log err
              null
            .then (response) ->
              unless response
                return
              $post = cheerio.load response
              body = $post('.article-detail').html()
              imageUrl = $post('.hero-wrapper').find('source').attr('data-srcset')?.split(' ')?[0]
              # if body.indexOf('Fam ') isnt -1
              #   return
              markdown = turndown.turndown body
              markdownLines = markdown.split('\n')
              title = markdownLines[3]
              markdownLines = _.takeRight markdownLines, markdownLines.length - 7
              markdown = markdownLines.join('\n')
              thread = {
                id: cknex.getTimeUuid(new Date(post.timestamp))
                groupId: CLASH_ROYALE_ES_GROUP_ID
                category: 'news'
                creatorId: CLASH_ROYALE_ES_USER_ID
                data:
                  title: title
                  body: markdown
                  attachments: if imageUrl
                    _.filter [
                      if post.thumbnail
                        {type: 'image', src: post.thumbnail, persist: true}
                      {type: 'image', src: imageUrl}
                    ]
                  extras:
                    newsRoyalePostId: post.id
              }
              Thread.upsert thread

module.exports = new NewsRoyaleService()
