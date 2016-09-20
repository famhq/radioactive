Joi = require 'joi'

uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
id =  Joi.string().regex uuidRegex

auth =
  accessToken: Joi.string()

user =
  id: id
  username: Joi.string().allow(null)

module.exports = {
  id
  auth
  user
}
