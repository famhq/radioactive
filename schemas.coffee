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


module.exports = {
  id
  auth
  user
  pushToken
}
