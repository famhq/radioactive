router = require 'exoid-router'

UserCtrl = require './controllers/user'
UserDataCtrl = require './controllers/user_data'
AuthCtrl = require './controllers/auth'
ChatMessageCtrl = require './controllers/chat_message'
ConversationCtrl = require './controllers/conversation'
TheadCtrl = require './controllers/thread'

authed = (handler) ->
  unless handler?
    return null

  (body, req, rest...) ->
    unless req.user?
      router.throw status: 401, detail: 'Unauthorized'

    handler body, req, rest...

module.exports = router
###################
# Public Routes   #
###################
.on 'auth.login', AuthCtrl.login

###################
# Authed Routes   #
###################
.on 'users.getMe', authed UserCtrl.getMe
.on 'users.getById', authed UserCtrl.getById
# .on 'users.updateMe', authed UserCtrl.updateMe
.on 'users.updateById', authed UserCtrl.updateById
.on 'users.searchByUsername', authed UserCtrl.searchByUsername
.on 'users.setUsername', authed UserCtrl.setUsername
.on 'users.setAvatarImage', authed UserCtrl.setAvatarImage

.on 'userData.getMe', authed UserDataCtrl.getMe
.on 'userData.getByUserId', authed UserDataCtrl.getByUserId
.on 'userData.updateMe', authed UserDataCtrl.updateMe
.on 'userData.followByUserId', authed UserDataCtrl.followByUserId
.on 'userData.unfollowByUserId', authed UserDataCtrl.unfollowByUserId
.on 'userData.blockByUserId', authed UserDataCtrl.blockByUserId
.on 'userData.unblockByUserId', authed UserDataCtrl.unblockByUserId
.on 'userData.deleteConversationByUserId',
  authed UserDataCtrl.deleteConversationByUserId

.on 'chatMessages.create', authed ChatMessageCtrl.create

.on 'threads.create', authed TheadCtrl.create
.on 'threads.getAll', authed TheadCtrl.getAll

.on 'conversation.getAll', authed ConversationCtrl.getAll
