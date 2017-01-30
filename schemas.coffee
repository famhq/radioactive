Joi = require 'joi'

uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
id =  Joi.string().regex uuidRegex

auth =
  accessToken: Joi.string()

user =
  id: id
  username: Joi.string().min(1).max(100).allow(null).regex /^[a-zA-Z0-9-_]+$/
  email: Joi.string().allow('')
  flags: Joi.object()
  isMember: Joi.boolean()
  data: Joi.object()
  avatarImage: Joi.object()
  embedded: Joi.array().allow(null).optional()

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
  # creatorId: id
  groupId: id.optional()
  title: Joi.string()
  summary: Joi.string()
  body: Joi.string()
  data: Joi.object()

module.exports = {
  id
  auth
  user
  pushToken
  event
  thread
}
