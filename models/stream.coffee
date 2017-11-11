Promise = require 'bluebird'
_ = require 'lodash'

StreamService = require '../services/stream'

class Stream
  streamCreate: (obj) =>
    channels = _.map @streamChannelsBy, (channelBy) =>
      channelById = obj[channelBy]
      "#{@streamChannelKey}:#{channelBy}:#{channelById}"
    StreamService.create obj, channels

  streamUpdateById: (id, obj) =>
    channels = _.map @streamChannelsBy, (channelBy) =>
      channelById = obj?[channelBy]
      "#{@streamChannelKey}:#{channelBy}:#{channelById}"
    StreamService.updateById id, obj, channels

  streamDeleteById: (id, obj) =>
    channels = _.map @streamChannelsBy, (channelBy) =>
      channelById = obj?[channelBy]
      "#{@streamChannelKey}:#{channelBy}:#{channelById}"
    StreamService.deleteById id, channels

  stream: ({emit, socket, route, channelBy, channelById, initial, postFn}) =>
    StreamService.stream {
      channel: "#{@streamChannelKey}:#{channelBy}:#{channelById}"
      emit
      socket
      route
      initial
      postFn
    }

module.exports = Stream
