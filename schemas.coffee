Joi = require 'joi'

uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
id =  Joi.string().regex uuidRegex

auth =
  accessToken: Joi.string()

user =
  id: id
  username: Joi.string().min(1).max(100).allow(null).regex /^[a-zA-Z0-9-_]+$/
  flags: Joi.object()
  data: Joi.object()
  avatarImage: Joi.object()
  embedded: Joi.array().allow(null).optional()

module.exports = {
  id
  auth
  user
}
