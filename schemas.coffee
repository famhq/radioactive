Joi = require 'joi'

uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
id =  Joi.string().regex uuidRegex

auth =
  accessToken: Joi.string()

user =
  id: id
  username: Joi.string().min(1).max(100).allow(null).regex /^[a-zA-Z0-9-_]+$/
  email: Joi.string().email().allow('')
  country: Joi.string().allow(null)
  flags: Joi.object()
  isMember: Joi.boolean()
  isOnline: Joi.boolean()
  isChatBanned: Joi.boolean()
  data: Joi.object()
  gameData: Joi.object().optional()
  fire: Joi.number().optional()
  avatarImage: Joi.object()
  embedded: Joi.array().allow(null).optional()
  joinTime: Joi.date().allow(null)

pushToken =
  id: id
  userId: id
  token: Joi.string()
  sourceType: Joi.string()

event =
  # id: id
  # creatorId: id
  groupId: id.optional()
  name: Joi.string()
  description: Joi.string()
  password: Joi.string().allow(null).optional()
  startTime: Joi.date()
  endTime: Joi.date()
  maxUserCount: Joi.number().optional()
  userIds: Joi.array().allow(null).optional()
  noUserIds: Joi.array().allow(null).optional()
  maybeUserIds: Joi.array().allow(null).optional()
  invitedUserIds: Joi.array().allow(null).optional()
  # visibility: Joi.string()
  # addTime: Joi.object()
  data: Joi.object()

thread =
  id: id.optional()
  groupId: id.optional()
  category: Joi.optional()
  creatorId: Joi.optional()
  timeBucket: Joi.optional()
  data: Joi.object()

module.exports = {
  id
  auth
  user
  pushToken
  event
  thread
}
