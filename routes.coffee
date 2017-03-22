router = require 'exoid-router'

UserCtrl = require './controllers/user'
UserDataCtrl = require './controllers/user_data'
UserGroupData = require './controllers/user_group_data'
UserGameData = require './controllers/user_game_data'
AuthCtrl = require './controllers/auth'
ChatMessageCtrl = require './controllers/chat_message'
ConversationCtrl = require './controllers/conversation'
ClashRoyaleAPICtrl = require './controllers/clash_royale_api'
ClashRoyaleDeckCtrl = require './controllers/clash_royale_deck'
ClashRoyaleUserDeckCtrl = require './controllers/clash_royale_user_deck'
ClashRoyaleCardCtrl = require './controllers/clash_royale_card'
EventCtrl = require './controllers/event'
PushTokenCtrl = require './controllers/push_token'
PaymentCtrl = require './controllers/payment'
TheadCtrl = require './controllers/thread'
GroupCtrl = require './controllers/group'
GroupRecordCtrl = require './controllers/group_record'
GroupRecordTypeCtrl = require './controllers/group_record_type'
GameRecordTypeCtrl = require './controllers/game_record_type'
ThreadCommentCtrl = require './controllers/thread_comment'
VideoCtrl = require './controllers/video'
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

###################
# Authed Routes   #
###################
.on 'users.getMe', authed UserCtrl.getMe
.on 'users.getById', authed UserCtrl.getById
.on 'users.updateById', authed UserCtrl.updateById
.on 'users.searchByUsername', authed UserCtrl.searchByUsername
.on 'users.setUsername', authed UserCtrl.setUsername
.on 'users.setAvatarImage', authed UserCtrl.setAvatarImage
.on 'users.setFlags', authed UserCtrl.setFlags
.on 'users.setFlagsById', authed UserCtrl.setFlagsById

.on 'userData.getMe', authed UserDataCtrl.getMe
.on 'userData.getByUserId', authed UserDataCtrl.getByUserId
.on 'userData.setAddress', authed UserDataCtrl.setAddress
.on 'userData.updateMe', authed UserDataCtrl.updateMe
.on 'userData.followByUserId', authed UserDataCtrl.followByUserId
.on 'userData.unfollowByUserId', authed UserDataCtrl.unfollowByUserId
.on 'userData.blockByUserId', authed UserDataCtrl.blockByUserId
.on 'userData.unblockByUserId', authed UserDataCtrl.unblockByUserId
.on 'userData.deleteConversationByUserId',
  authed UserDataCtrl.deleteConversationByUserId

.on 'chatMessages.create', authed ChatMessageCtrl.create
.on 'chatMessages.uploadImage', authed ChatMessageCtrl.uploadImage
.on 'chatMessages.getAllByConversationId',
  authed ChatMessageCtrl.getAllByConversationId

.on 'pushTokens.create', authed PushTokenCtrl.create
.on 'pushTokens.updateByToken', authed PushTokenCtrl.updateByToken

.on 'threads.create', authed TheadCtrl.createOrUpdateById
.on 'threads.getAll', authed TheadCtrl.getAll
.on 'threads.getById', authed TheadCtrl.getById
.on 'threads.voteById', authed TheadCtrl.voteById
.on 'threads.updateById', authed TheadCtrl.createOrUpdateById

.on 'events.create', authed EventCtrl.create
.on 'events.updateById', authed EventCtrl.updateById
.on 'events.getById', authed EventCtrl.getById
.on 'events.getAll', authed EventCtrl.getAll
.on 'events.joinById', authed EventCtrl.joinById
.on 'events.leaveById', authed EventCtrl.leaveById
.on 'events.deleteById', authed EventCtrl.deleteById

.on 'groups.create', authed GroupCtrl.create
.on 'groups.updateById', authed GroupCtrl.updateById
.on 'groups.joinById', authed GroupCtrl.joinById
.on 'groups.leaveById', authed GroupCtrl.leaveById
.on 'groups.getAll', authed GroupCtrl.getAll
.on 'groups.getById', authed GroupCtrl.getById
.on 'groups.inviteById', authed GroupCtrl.inviteById

.on 'groupRecords.getAllByUserIdAndGroupId',
  authed GroupRecordCtrl.getAllByUserIdAndGroupId
.on 'groupRecords.save', authed GroupRecordCtrl.save
.on 'groupRecords.bulkSave', authed GroupRecordCtrl.bulkSave

.on 'groupRecordTypes.getAllByGroupId',
  authed GroupRecordTypeCtrl.getAllByGroupId
.on 'groupRecordTypes.create', authed GroupRecordTypeCtrl.create
.on 'groupRecordTypes.deleteById', authed GroupRecordTypeCtrl.deleteById

.on 'gameRecordTypes.getAllByUserIdAndGameId',
  authed GameRecordTypeCtrl.getAllByUserIdAndGameId

.on 'userGroupData.updateMeByGroupId', authed UserGroupData.updateMeByGroupId
.on 'userGroupData.getMeByGroupId', authed UserGroupData.getMeByGroupId

.on 'userGameData.getByUserIdAndGameId',
  authed UserGameData.getByUserIdAndGameId

.on 'threadComments.create', authed ThreadCommentCtrl.create
.on 'threadComments.flag', authed ThreadCommentCtrl.flag
.on 'threadComments.getAllByThreadId', authed ThreadCommentCtrl.getAllByThreadId

.on 'payments.verify', authed PaymentCtrl.verify
.on 'payments.purchase', authed PaymentCtrl.purchase

.on 'conversations.create', authed ConversationCtrl.create
.on 'conversations.updateById', authed ConversationCtrl.updateById
.on 'conversations.getAll', authed ConversationCtrl.getAll
.on 'conversations.getById', authed ConversationCtrl.getById

.on 'clashRoyaleAPI.refreshByPlayerTag',
  authed ClashRoyaleAPICtrl.refreshByPlayerTag

.on 'clashRoyaleDecks.getAll', authed ClashRoyaleDeckCtrl.getAll
.on 'clashRoyaleDecks.getById', authed ClashRoyaleDeckCtrl.getById

.on 'clashRoyaleUserDecks.create', authed ClashRoyaleUserDeckCtrl.create
.on 'clashRoyaleUserDecks.getAll', authed ClashRoyaleUserDeckCtrl.getAll
.on 'clashRoyaleUserDecks.getFavoritedDeckIds',
  authed ClashRoyaleUserDeckCtrl.getFavoritedDeckIds
.on 'clashRoyaleUserDecks.getAllByUserId',
  authed ClashRoyaleUserDeckCtrl.getAllByUserId
.on 'clashRoyaleUserDecks.getByDeckId',
  authed ClashRoyaleUserDeckCtrl.getByDeckId
.on 'clashRoyaleUserDecks.favorite', authed ClashRoyaleUserDeckCtrl.favorite
.on 'clashRoyaleUserDecks.unfavorite', authed ClashRoyaleUserDeckCtrl.unfavorite

.on 'clashRoyaleCards.getAll', authed ClashRoyaleCardCtrl.getAll
.on 'clashRoyaleCards.getById', authed ClashRoyaleCardCtrl.getById
.on 'clashRoyaleCards.getByKey', authed ClashRoyaleCardCtrl.getByKey

.on 'videos.getAll', authed VideoCtrl.getAll
.on 'videos.getById', authed VideoCtrl.getById
