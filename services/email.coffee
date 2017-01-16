email = require 'emailjs'
Promise = require 'bluebird'
log = require 'loga'

config = require '../config'

FROM_EMAIL = 'Starfire <noreply@starfi.re>'

server = email.server.connect
  user: config.GMAIL.USER
  password: config.GMAIL.PASS
  host: 'smtp.gmail.com'
  ssl: true

class EmailService
  EMAILS:
    OPS: 'Ops <ops@clay.io>'
    EVERYONE: 'Everyone <everyone@clay.io>'
    CUSTOMER_FOLLOWUP: 'Cristian Ruiz <cristian@clay.io>, ' +
                        'Austin Hallock <austin@clay.io>'

  send: ({to, subject, text}) ->
    if config.ENV is config.ENVS.TEST
      log.info "[TEST] Sending email to #{to}, subject:", subject
      return Promise.resolve(null)

    if config.ENV is config.ENVS.DEV
      log.info "[DEV] Sending email to #{to} ops: ", subject, text
      return Promise.resolve(null)

    if config.IS_STAGING
      log.info "[STAGING] Sending email to #{to} ops: ", subject, text
      return Promise.resolve(null)

    Promise.promisify(server.send, server)
      text: text
      from: 'Starfire <noreply@starfi.re>'
      to: to
      subject: subject

module.exports = new EmailService()
