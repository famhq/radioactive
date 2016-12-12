router = require 'exoid-router'

UserCtrl = require './controllers/user'
UserDataCtrl = require './controllers/user_data'
AuthCtrl = require './controllers/auth'
ChatMessageCtrl = require './controllers/chat_message'
ConversationCtrl = require './controllers/conversation'
ClashRoyaleDeckCtrl = require './controllers/clash_royale_deck'
ClashRoyaleUserDeckCtrl = require './controllers/clash_royale_user_deck'
ClashRoyaleCardCtrl = require './controllers/clash_royale_card'
PushTokenCtrl = require './controllers/push_token'
PaymentCtrl = require './controllers/payment'
TheadCtrl = require './controllers/thread'
GroupCtrl = require './controllers/group'
ThreadMessageCtrl = require './controllers/thread_message'
StreamService = require './services/stream'

authed = (handler) ->
  unless handler?
    return null

  (body, req, rest...) ->
    unless req.user?
      router.throw status: 401, info: 'Unauthorized'

    handler body, req, rest...

module.exports = router
###################
# Public Routes   #
###################
.on 'auth.join', AuthCtrl.join
.on 'auth.login', AuthCtrl.login
.on 'auth.loginUsername', AuthCtrl.loginUsername
.on 'auth.loginCode', AuthCtrl.loginCode

###################
# Authed Routes   #
###################
.on 'users.getMe', authed UserCtrl.getMe
.on 'users.getById', authed UserCtrl.getById
.on 'users.getByCode', authed UserCtrl.getByCode
# .on 'users.makeMember', authed UserCtrl.makeMember
.on 'users.updateById', authed UserCtrl.updateById
.on 'users.searchByUsername', authed UserCtrl.searchByUsername
.on 'users.setUsername', authed UserCtrl.setUsername
.on 'users.setAvatarImage', authed UserCtrl.setAvatarImage
.on 'users.setFlags', authed UserCtrl.setFlags
.on 'users.requestInvite', authed UserCtrl.requestInvite

.on 'userData.getMe', authed UserDataCtrl.getMe
.on 'userData.getByUserId', authed UserDataCtrl.getByUserId
.on 'userData.setAddress', authed UserDataCtrl.setAddress
.on 'userData.setClashRoyaleDeckId', authed UserDataCtrl.setClashRoyaleDeckId
.on 'userData.updateMe', authed UserDataCtrl.updateMe
.on 'userData.followByUserId', authed UserDataCtrl.followByUserId
.on 'userData.unfollowByUserId', authed UserDataCtrl.unfollowByUserId
.on 'userData.blockByUserId', authed UserDataCtrl.blockByUserId
.on 'userData.unblockByUserId', authed UserDataCtrl.unblockByUserId
.on 'userData.deleteConversationByUserId',
  authed UserDataCtrl.deleteConversationByUserId

.on 'chatMessages.create', authed ChatMessageCtrl.create
.on 'chatMessages.getAllByConversationId',
  authed ChatMessageCtrl.getAllByConversationId

.on 'pushTokens.create', authed PushTokenCtrl.create
.on 'pushTokens.updateByToken', authed PushTokenCtrl.updateByToken

.on 'threads.create', authed TheadCtrl.create
.on 'threads.getAll', authed TheadCtrl.getAll
.on 'threads.getById', authed TheadCtrl.getById

.on 'groups.create', authed GroupCtrl.create
.on 'groups.updateById', authed GroupCtrl.updateById
.on 'groups.joinById', authed GroupCtrl.joinById
.on 'groups.getAll', authed GroupCtrl.getAll
.on 'groups.getById', authed GroupCtrl.getById

.on 'threadMessages.create', authed ThreadMessageCtrl.create
.on 'threadMessages.flag', authed ThreadMessageCtrl.flag

.on 'payments.verify', authed PaymentCtrl.verify
.on 'payments.purchase', authed PaymentCtrl.purchase

.on 'conversations.create', authed ConversationCtrl.create
.on 'conversations.getAll', authed ConversationCtrl.getAll
.on 'conversations.getByGroupId', authed ConversationCtrl.getByGroupId
.on 'conversations.getById', authed ConversationCtrl.getById

.on 'clashRoyaleDeck.getAll', authed ClashRoyaleDeckCtrl.getAll
.on 'clashRoyaleDeck.getById', authed ClashRoyaleDeckCtrl.getById

.on 'clashRoyaleUserDeck.create', authed ClashRoyaleUserDeckCtrl.create
.on 'clashRoyaleUserDeck.getByDeckId',
  authed ClashRoyaleUserDeckCtrl.getByDeckId
.on 'clashRoyaleUserDeck.favorite', authed ClashRoyaleUserDeckCtrl.favorite
.on 'clashRoyaleUserDeck.unfavorite', authed ClashRoyaleUserDeckCtrl.unfavorite
.on 'clashRoyaleUserDeck.incrementByDeckId',
  authed ClashRoyaleUserDeckCtrl.incrementByDeckId

.on 'clashRoyaleCard.getAll', authed ClashRoyaleCardCtrl.getAll
.on 'clashRoyaleCard.getById', authed ClashRoyaleCardCtrl.getById
