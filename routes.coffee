router = require 'exoid-router'

AddonCtrl = require './controllers/addon'
AuthCtrl = require './controllers/auth'
ChatMessageCtrl = require './controllers/chat_message'
ClanCtrl = require './controllers/clan'
ConversationCtrl = require './controllers/conversation'
ClanRecordTypeCtrl = require './controllers/clan_record_type'
ClashRoyaleAPICtrl = require './controllers/clash_royale_api'
ClashRoyaleMatchCtrl = require './controllers/clash_royale_match'
ClashRoyaleDeckCtrl = require './controllers/clash_royale_deck'
ClashRoyalePlayerDeckCtrl = require './controllers/clash_royale_player_deck'
ClashRoyaleCardCtrl = require './controllers/clash_royale_card'
DynamicImageCtrl = require './controllers/dynamic_image'
EventCtrl = require './controllers/event'
ItemCtrl = require './controllers/item'
ModCtrl = require './controllers/mod'
NpsCtrl = require './controllers/nps'
PaymentCtrl = require './controllers/payment'
PushTokenCtrl = require './controllers/push_token'
PlayerCtrl = require './controllers/player'
GroupCtrl = require './controllers/group'
GroupUserCtrl = require './controllers/group_user'
GroupRecordCtrl = require './controllers/group_record'
GroupRecordTypeCtrl = require './controllers/group_record_type'
GameRecordTypeCtrl = require './controllers/game_record_type'
GroupUserXpTransactionCtrl = require './controllers/group_user_xp_transaction'
ProductCtrl = require './controllers/product'
RewardCtrl = require './controllers/reward'
StarCtrl = require './controllers/star'
TheadCtrl = require './controllers/thread'
ThreadCommentCtrl = require './controllers/thread_comment'
ThreadVoteCtrl = require './controllers/thread_vote'
UserCtrl = require './controllers/user'
UserFollowerCtrl = require './controllers/user_follower'
UserDataCtrl = require './controllers/user_data'
UserItemCtrl = require './controllers/user_item'
UserGroupDataCtrl = require './controllers/user_group_data'
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
.on 'users.getByUsername', authed UserCtrl.getByUsername
.on 'users.updateById', authed UserCtrl.updateById
.on 'users.getAllByPlayerIdAndGameId', authed UserCtrl.getAllByPlayerIdAndGameId
.on 'users.searchByUsername', authed UserCtrl.searchByUsername
.on 'users.setUsername', authed UserCtrl.setUsername
.on 'users.setLanguage', authed UserCtrl.setLanguage
.on 'users.setAvatarImage', authed UserCtrl.setAvatarImage
.on 'users.setFlags', authed UserCtrl.setFlags
.on 'users.setFlagsById', authed UserCtrl.setFlagsById

.on 'userData.getMe', authed UserDataCtrl.getMe
.on 'userData.getByUserId', authed UserDataCtrl.getByUserId
.on 'userData.setAddress', authed UserDataCtrl.setAddress
.on 'userData.updateMe', authed UserDataCtrl.updateMe
.on 'userData.blockByUserId', authed UserDataCtrl.blockByUserId
.on 'userData.unblockByUserId', authed UserDataCtrl.unblockByUserId
.on 'userData.deleteConversationByUserId',
  authed UserDataCtrl.deleteConversationByUserId

.on 'userFollowers.getAllFollowingIds',
  authed UserFollowerCtrl.getAllFollowingIds
.on 'userFollowers.getAllFollowerIds',
  authed UserFollowerCtrl.getAllFollowerIds
.on 'userFollowers.followByUserId',
  authed UserFollowerCtrl.followByUserId
.on 'userFollowers.unfollowByUserId',
  authed UserFollowerCtrl.unfollowByUserId

.on 'addons.getAll', authed AddonCtrl.getAll
.on 'addons.getById', authed AddonCtrl.getById
.on 'addons.getByKey', authed AddonCtrl.getByKey
.on 'addons.voteById', authed AddonCtrl.voteById

.on 'clanRecordTypes.getAllByClanIdAndGameId',
  authed ClanRecordTypeCtrl.getAllByClanIdAndGameId

.on 'chatMessages.create', authed ChatMessageCtrl.create
.on 'chatMessages.deleteById', authed ChatMessageCtrl.deleteById
.on 'chatMessages.uploadImage', authed ChatMessageCtrl.uploadImage
.on 'chatMessages.getAllByConversationId',
  authed ChatMessageCtrl.getAllByConversationId

.on 'pushTokens.create', authed PushTokenCtrl.create
.on 'pushTokens.updateByToken', authed PushTokenCtrl.updateByToken
.on 'pushTokens.subscribeToTopic', authed PushTokenCtrl.subscribeToTopic

.on 'dynamicImage.getMeByImageKey',
  authed DynamicImageCtrl.getMeByImageKey
.on 'dynamicImage.upsertMeByImageKey',
  authed DynamicImageCtrl.upsertMeByImageKey

.on 'threads.create', authed TheadCtrl.createOrUpdateById
.on 'threads.getAll', authed TheadCtrl.getAll
.on 'threads.getById', authed TheadCtrl.getById
.on 'threads.voteById', authed TheadCtrl.voteById
.on 'threads.updateById', authed TheadCtrl.createOrUpdateById
.on 'threads.deleteById', authed TheadCtrl.deleteById

.on 'threadVotes.upsertByParent',
  authed ThreadVoteCtrl.upsertByParent

.on 'threadComments.create', authed ThreadCommentCtrl.create
.on 'threadComments.flag', authed ThreadCommentCtrl.flag
.on 'threadComments.getAllByThreadId',
  authed ThreadCommentCtrl.getAllByThreadId

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
.on 'groups.getByKey', authed GroupCtrl.getByKey
.on 'groups.inviteById', authed GroupCtrl.inviteById

.on 'groupUsers.createModeratorByUsername',
  authed GroupUserCtrl.createModeratorByUsername
.on 'groupUsers.getByGroupIdAndUserId',
  authed GroupUserCtrl.getByGroupIdAndUserId
.on 'groupUsers.getTopByGroupId', authed GroupUserCtrl.getTopByGroupId

.on 'groupUserXpTransactions.getAllByGroupId',
  authed GroupUserXpTransactionCtrl.getAllByGroupId
.on 'groupUserXpTransactions.incrementByGroupIdAndActionKey',
  authed GroupUserXpTransactionCtrl.incrementByGroupIdAndActionKey

.on 'groupRecords.getAllByUserIdAndGroupId',
  authed GroupRecordCtrl.getAllByUserIdAndGroupId
.on 'groupRecords.save', authed GroupRecordCtrl.save
.on 'groupRecords.bulkSave', authed GroupRecordCtrl.bulkSave

.on 'groupRecordTypes.getAllByGroupId',
  authed GroupRecordTypeCtrl.getAllByGroupId
.on 'groupRecordTypes.create', authed GroupRecordTypeCtrl.create
.on 'groupRecordTypes.deleteById', authed GroupRecordTypeCtrl.deleteById

.on 'gameRecordTypes.getAllByPlayerIdAndGameId',
  authed GameRecordTypeCtrl.getAllByPlayerIdAndGameId

.on 'userGroupData.updateMeByGroupId',
  authed UserGroupDataCtrl.updateMeByGroupId
.on 'userGroupData.getMeByGroupId', authed UserGroupDataCtrl.getMeByGroupId

.on 'userItems.getAll', authed UserItemCtrl.getAll
.on 'userItems.upgradeByItemKey', authed UserItemCtrl.upgradeByItemKey

.on 'players.getByUserIdAndGameId',
  authed PlayerCtrl.getByUserIdAndGameId
.on 'players.getByPlayerIdAndGameId',
  authed PlayerCtrl.getByPlayerIdAndGameId
.on 'players.getTop', authed PlayerCtrl.getTop
.on 'players.search', authed PlayerCtrl.search
.on 'players.getMeFollowing', authed PlayerCtrl.getMeFollowing
.on 'players.verifyMe', authed PlayerCtrl.verifyMe
.on 'players.getVerifyDeckId', authed PlayerCtrl.getVerifyDeckId
.on 'players.getIsAutoRefreshByPlayerIdAndGameId',
  authed PlayerCtrl.getIsAutoRefreshByPlayerIdAndGameId
.on 'players.setAutoRefreshByGameId',
  authed PlayerCtrl.setAutoRefreshByGameId

.on 'clan.getById', authed ClanCtrl.getById
.on 'clan.getByClanIdAndGameId', authed ClanCtrl.getByClanIdAndGameId
.on 'clan.claimById', authed ClanCtrl.claimById
.on 'clan.joinById', authed ClanCtrl.joinById
.on 'clan.updateById', authed ClanCtrl.updateById
# .on 'clan.search', authed ClanCtrl.search

.on 'payments.verify', authed PaymentCtrl.verify
.on 'payments.purchase', authed PaymentCtrl.purchase

.on 'conversations.create', authed ConversationCtrl.create
.on 'conversations.updateById', authed ConversationCtrl.updateById
.on 'conversations.getAll', authed ConversationCtrl.getAll
.on 'conversations.getById', authed ConversationCtrl.getById

.on 'clashRoyaleAPI.setByPlayerId',
  authed ClashRoyaleAPICtrl.setByPlayerId
.on 'clashRoyaleAPI.refreshByPlayerId',
  authed ClashRoyaleAPICtrl.refreshByPlayerId
.on 'clashRoyaleAPI.refreshByClanId',
  authed ClashRoyaleAPICtrl.refreshByClanId

.on 'clashRoyaleDecks.getById', authed ClashRoyaleDeckCtrl.getById

.on 'clashRoyalePlayerDecks.getAllByPlayerId',
  authed ClashRoyalePlayerDeckCtrl.getAllByPlayerId
.on 'clashRoyalePlayerDecks.getByDeckIdAndPlayerId',
  authed ClashRoyalePlayerDeckCtrl.getByDeckIdAndPlayerId

.on 'clashRoyaleCards.getAll', authed ClashRoyaleCardCtrl.getAll
.on 'clashRoyaleCards.getById', authed ClashRoyaleCardCtrl.getById
.on 'clashRoyaleCards.getByKey', authed ClashRoyaleCardCtrl.getByKey
.on 'clashRoyaleCards.getChestCards', authed ClashRoyaleCardCtrl.getChestCards
.on 'clashRoyaleCards.getTop', authed ClashRoyaleCardCtrl.getTop

.on 'clashRoyaleMatches.getAllByUserId',
  authed ClashRoyaleMatchCtrl.getAllByUserId
.on 'clashRoyaleMatches.getAllByPlayerId',
  authed ClashRoyaleMatchCtrl.getAllByPlayerId

.on 'nps.create', authed NpsCtrl.create

.on 'items.getAllByGroupId', authed ItemCtrl.getAllByGroupId
.on 'items.getAll', authed ItemCtrl.getAll

.on 'mods.getAllBanned', authed ModCtrl.getAllBanned
.on 'mods.getAllReportedMessages', authed ModCtrl.getAllReportedMessages
.on 'mods.banByIp', authed ModCtrl.banByIp
.on 'mods.banByUserId', authed ModCtrl.banByUserId
.on 'mods.unbanByUserId', authed ModCtrl.unbanByUserId
.on 'mods.unflagByChatMessageId', authed ModCtrl.unflagByChatMessageId

.on 'products.getAllByGroupId', authed ProductCtrl.getAllByGroupId
.on 'products.buy', authed ProductCtrl.buy

.on 'rewards.setup', authed RewardCtrl.setup
.on 'rewards.getAll', authed RewardCtrl.getAll
.on 'rewards.incrementAttemptsByNetworkAndOfferId',
  authed RewardCtrl.incrementAttemptsByNetworkAndOfferId

.on 'stars.getByUsername', authed StarCtrl.getByUsername
.on 'stars.getAll', authed StarCtrl.getAll

.on 'videos.getAllByGroupId', authed VideoCtrl.getAllByGroupId
.on 'videos.getById', authed VideoCtrl.getById
.on 'videos.logViewById', authed VideoCtrl.logViewById
