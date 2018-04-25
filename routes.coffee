router = require 'exoid-router'

AddonCtrl = require './controllers/addon'
AppInstallActionCtrl = require './controllers/app_install_action'
AuthCtrl = require './controllers/auth'
ChatMessageCtrl = require './controllers/chat_message'
ClanCtrl = require './controllers/clan'
ConnectionCtrl = require './controllers/connection'
ConversationCtrl = require './controllers/conversation'
ClanRecordTypeCtrl = require './controllers/clan_record_type'
ClashRoyaleAPICtrl = require './controllers/clash_royale_api'
ClashRoyaleMatchCtrl = require './controllers/clash_royale_match'
ClashRoyaleDeckCtrl = require './controllers/clash_royale_deck'
ClashRoyalePlayerDeckCtrl = require './controllers/clash_royale_player_deck'
ClashRoyaleCardCtrl = require './controllers/clash_royale_card'
DynamicImageCtrl = require './controllers/dynamic_image'
EventCtrl = require './controllers/event'
FortniteWeaponCtrl = require './controllers/fortnite_weapon'
IapCtrl = require './controllers/iap'
ItemCtrl = require './controllers/item'
BanCtrl = require './controllers/ban'
NotificationCtrl = require './controllers/notification'
NpsCtrl = require './controllers/nps'
PaymentCtrl = require './controllers/payment'
PushTokenCtrl = require './controllers/push_token'
PlayerCtrl = require './controllers/player'
GroupCtrl = require './controllers/group'
GroupAuditLogCtrl = require './controllers/group_audit_log'
GroupUserCtrl = require './controllers/group_user'
GroupRecordCtrl = require './controllers/group_record'
GroupRecordTypeCtrl = require './controllers/group_record_type'
GameRecordTypeCtrl = require './controllers/game_record_type'
GroupRoleCtrl = require './controllers/group_role'
GroupPageCtrl = require './controllers/group_page'
EarnActionCtrl = require './controllers/earn_action'
LfgCtrl = require './controllers/lfg'
PollCtrl = require './controllers/poll'
ProductCtrl = require './controllers/product'
RewardCtrl = require './controllers/reward'
SpecialOfferCtrl = require './controllers/special_offer'
StarCtrl = require './controllers/star'
ThreadCtrl = require './controllers/thread'
ThreadCommentCtrl = require './controllers/thread_comment'
ThreadVoteCtrl = require './controllers/thread_vote'
TradeCtrl = require './controllers/trade'
UserCtrl = require './controllers/user'
UserBlockCtrl = require './controllers/user_block'
UserFollowerCtrl = require './controllers/user_follower'
UserItemCtrl = require './controllers/user_item'
VideoCtrl = require './controllers/video'
StreamService = require './services/stream'

authed = (handler) ->
  unless handler?
    return null

  (body, req, rest...) ->
    unless req.user?
      router.throw status: 401, info: 'Unauthorized', ignoreLog: true

    handler body, req, rest...

module.exports = router
###################
# Public Routes   #
###################
.on 'auth.join', AuthCtrl.join
.on 'auth.login', AuthCtrl.login
.on 'auth.loginUsername', AuthCtrl.loginUsername
.on 'auth.loginTwitchExtension', AuthCtrl.loginTwitchExtension
.on 'auth.loginTwitch', AuthCtrl.loginTwitch

###################
# Authed Routes   #
###################
.on 'users.getMe', authed UserCtrl.getMe
.on 'users.getById', authed UserCtrl.getById
.on 'users.getByUsername', authed UserCtrl.getByUsername
.on 'users.updateById', authed UserCtrl.updateById
.on 'users.getAllByPlayerIdAndGameKey', authed UserCtrl.getAllByPlayerIdAndGameKey
.on 'users.searchByUsername', authed UserCtrl.searchByUsername
.on 'users.setUsername', authed UserCtrl.setUsername
.on 'users.setLanguage', authed UserCtrl.setLanguage
.on 'users.setAvatarImage', authed UserCtrl.setAvatarImage
.on 'users.setFlags', authed UserCtrl.setFlags
.on 'users.setFlagsById', authed UserCtrl.setFlagsById
.on 'users.getCountry', authed UserCtrl.getCountry

.on 'userFollowers.getAllFollowingIds',
  authed UserFollowerCtrl.getAllFollowingIds
.on 'userFollowers.getAllFollowerIds',
  authed UserFollowerCtrl.getAllFollowerIds
.on 'userFollowers.getAllFollowing',
  authed UserFollowerCtrl.getAllFollowing
.on 'userFollowers.getAllFollowers',
  authed UserFollowerCtrl.getAllFollowers
.on 'userFollowers.followByUserId',
  authed UserFollowerCtrl.followByUserId
.on 'userFollowers.unfollowByUserId',
  authed UserFollowerCtrl.unfollowByUserId

.on 'userBlocks.getAll',
  authed UserBlockCtrl.getAll
.on 'userBlocks.getAllIds',
  authed UserBlockCtrl.getAllIds
.on 'userBlocks.blockByUserId',
  authed UserBlockCtrl.blockByUserId
.on 'userBlocks.unblockByUserId',
  authed UserBlockCtrl.unblockByUserId

.on 'addons.getAll', authed AddonCtrl.getAll
.on 'addons.getAllByGroupId', authed AddonCtrl.getAllByGroupId
.on 'addons.getById', authed AddonCtrl.getById
.on 'addons.getByKey', authed AddonCtrl.getByKey
.on 'addons.voteById', authed AddonCtrl.voteById

.on 'appInstallActions.upsert', authed AppInstallActionCtrl.upsert
.on 'appInstallActions.get', authed AppInstallActionCtrl.get

.on 'clanRecordTypes.getAllByClanIdAndGameKey',
  authed ClanRecordTypeCtrl.getAllByClanIdAndGameKey

.on 'chatMessages.create', authed ChatMessageCtrl.create
.on 'chatMessages.deleteById', authed ChatMessageCtrl.deleteById
.on 'chatMessages.deleteAllByGroupIdAndUserId',
  authed ChatMessageCtrl.deleteAllByGroupIdAndUserId
.on 'chatMessages.getLastTimeByMeAndConversationId',
  authed ChatMessageCtrl.getLastTimeByMeAndConversationId
.on 'chatMessages.uploadImage', authed ChatMessageCtrl.uploadImage
.on 'chatMessages.getAllByConversationId',
  authed ChatMessageCtrl.getAllByConversationId
.on 'chatMessages.unsubscribeByConversationId',
  authed ChatMessageCtrl.unsubscribeByConversationId

.on 'pushTokens.upsert', authed PushTokenCtrl.upsert
.on 'pushTokens.subscribeToTopic', authed PushTokenCtrl.subscribeToTopic

.on 'dynamicImage.getMeByImageKey',
  authed DynamicImageCtrl.getMeByImageKey
.on 'dynamicImage.upsertMeByImageKey',
  authed DynamicImageCtrl.upsertMeByImageKey

.on 'threads.upsert', authed ThreadCtrl.upsert
.on 'threads.getAll', authed ThreadCtrl.getAll
.on 'threads.getById', authed ThreadCtrl.getById
.on 'threads.voteById', authed ThreadCtrl.voteById
.on 'threads.pinById', authed ThreadCtrl.pinById
.on 'threads.unpinById', authed ThreadCtrl.unpinById
.on 'threads.deleteById', authed ThreadCtrl.deleteById

.on 'threadVotes.upsertByParent',
  authed ThreadVoteCtrl.upsertByParent

.on 'threadComments.create', authed ThreadCommentCtrl.create
.on 'threadComments.flag', authed ThreadCommentCtrl.flag
.on 'threadComments.getAllByThreadId',
  authed ThreadCommentCtrl.getAllByThreadId
.on 'threadComments.deleteByThreadComment',
  authed ThreadCommentCtrl.deleteByThreadComment
.on 'threadComments.deleteAllByGroupIdAndUserId',
  authed ThreadCommentCtrl.deleteAllByGroupIdAndUserId

.on 'events.create', authed EventCtrl.create
.on 'events.updateById', authed EventCtrl.updateById
.on 'events.getById', authed EventCtrl.getById
.on 'events.getAll', authed EventCtrl.getAll
.on 'events.joinById', authed EventCtrl.joinById
.on 'events.leaveById', authed EventCtrl.leaveById
.on 'events.deleteById', authed EventCtrl.deleteById

.on 'fortniteWeapons.getAll', authed FortniteWeaponCtrl.getAll

.on 'groups.create', authed GroupCtrl.create
.on 'groups.updateById', authed GroupCtrl.updateById
.on 'groups.joinById', authed GroupCtrl.joinById
.on 'groups.leaveById', authed GroupCtrl.leaveById
.on 'groups.getAll', authed GroupCtrl.getAll
.on 'groups.getAllByUserId', authed GroupCtrl.getAllByUserId
.on 'groups.getAllChannelsById', authed GroupCtrl.getAllChannelsById
.on 'groups.getById', authed GroupCtrl.getById
.on 'groups.getByKey', authed GroupCtrl.getByKey
.on 'groups.getByGameKeyAndLanguage', authed GroupCtrl.getByGameKeyAndLanguage
.on 'groups.inviteById', authed GroupCtrl.inviteById
.on 'groups.sendNotificationById', authed GroupCtrl.sendNotificationById

.on 'groupAuditLogs.getAllByGroupId',
  authed GroupAuditLogCtrl.getAllByGroupId

.on 'groupUsers.addRoleByGroupIdAndUserId',
  authed GroupUserCtrl.addRoleByGroupIdAndUserId
.on 'groupUsers.removeRoleByGroupIdAndUserId',
  authed GroupUserCtrl.removeRoleByGroupIdAndUserId
.on 'groupUsers.addXpByGroupIdAndUserId',
  authed GroupUserCtrl.addXpByGroupIdAndUserId
.on 'groupUsers.getByGroupIdAndUserId',
  authed GroupUserCtrl.getByGroupIdAndUserId
.on 'groupUsers.getTopByGroupId', authed GroupUserCtrl.getTopByGroupId
.on 'groupUsers.getMeSettingsByGroupId',
  authed GroupUserCtrl.getMeSettingsByGroupId
.on 'groupUsers.updateMeSettingsByGroupId',
  authed GroupUserCtrl.updateMeSettingsByGroupId
.on 'groupUsers.getOnlineCountByGroupId',
  authed GroupUserCtrl.getOnlineCountByGroupId

.on 'earnActions.getAllByGroupId',
  authed EarnActionCtrl.getAllByGroupId
.on 'earnActions.incrementByGroupIdAndAction',
  authed EarnActionCtrl.incrementByGroupIdAndAction

.on 'groupPages.getAllByGroupId',
  authed GroupPageCtrl.getAllByGroupId
.on 'groupPages.upsert',
  authed GroupPageCtrl.upsert
.on 'groupPages.deleteByGroupIdAndKey',
  authed GroupPageCtrl.deleteByGroupIdAndKey
.on 'groupPages.getByGroupIdAndKey',
  authed GroupPageCtrl.getByGroupIdAndKey

.on 'groupRecords.getAllByGroupIdAndRecordTypeKey',
  authed GroupRecordCtrl.getAllByGroupIdAndRecordTypeKey

.on 'groupRecordTypes.getAllByGroupId',
  authed GroupRecordTypeCtrl.getAllByGroupId
.on 'groupRecordTypes.create', authed GroupRecordTypeCtrl.create
.on 'groupRecordTypes.deleteById', authed GroupRecordTypeCtrl.deleteById

.on 'gameRecordTypes.getAllByPlayerIdAndGameKey',
  authed GameRecordTypeCtrl.getAllByPlayerIdAndGameKey

.on 'groupRoles.getAllByGroupId', authed GroupRoleCtrl.getAllByGroupId
.on 'groupRoles.createByGroupId', authed GroupRoleCtrl.createByGroupId
.on 'groupRoles.updatePermissions', authed GroupRoleCtrl.updatePermissions
.on 'groupRoles.deleteByGroupIdAndRoleId',
  authed GroupRoleCtrl.deleteByGroupIdAndRoleId

.on 'trade.getById', authed TradeCtrl.getById
.on 'trade.create', authed TradeCtrl.create
.on 'trade.getAll', authed TradeCtrl.getAll
.on 'trade.declineById', authed TradeCtrl.declineById
.on 'trade.deleteById', authed TradeCtrl.deleteById
.on 'trade.updateById', authed TradeCtrl.updateById

.on 'time.get', authed -> {now: new Date()}


.on 'userItems.getAll', authed UserItemCtrl.getAll
.on 'userItems.getByItemKey', authed UserItemCtrl.getByItemKey
.on 'userItems.getAllByUserId', authed UserItemCtrl.getAllByUserId
.on 'userItems.consumeByItemKey', authed UserItemCtrl.consumeByItemKey
.on 'userItems.openByItemKey', authed UserItemCtrl.openByItemKey

.on 'players.getByUserIdAndGameKey',
  authed PlayerCtrl.getByUserIdAndGameKey
.on 'players.getByPlayerIdAndGameKey',
  authed PlayerCtrl.getByPlayerIdAndGameKey
.on 'players.getAllByMe',
  authed PlayerCtrl.getAllByMe
.on 'players.unlinkByMeAndGameKey',
  authed PlayerCtrl.unlinkByMeAndGameKey
.on 'players.getTop', authed PlayerCtrl.getTop
.on 'players.search', authed PlayerCtrl.search
.on 'players.getMeFollowing', authed PlayerCtrl.getMeFollowing
.on 'players.verifyMe', authed PlayerCtrl.verifyMe
.on 'players.getVerifyDeckId', authed PlayerCtrl.getVerifyDeckId
.on 'players.getIsAutoRefreshByPlayerIdAndGameKey',
  authed PlayerCtrl.getIsAutoRefreshByPlayerIdAndGameKey
.on 'players.setAutoRefreshByGameKey',
  authed PlayerCtrl.setAutoRefreshByGameKey
.on 'players.setByPlayerIdAndGameKey',
  authed PlayerCtrl.setByPlayerIdAndGameKey
.on 'players.refreshByPlayerIdAndGameKey',
  authed PlayerCtrl.refreshByPlayerIdAndGameKey

.on 'clan.getById', authed ClanCtrl.getById
.on 'clan.getByClanIdAndGameKey', authed ClanCtrl.getByClanIdAndGameKey
.on 'clan.claimById', authed ClanCtrl.claimById
.on 'clan.joinById', authed ClanCtrl.joinById
.on 'clan.updateById', authed ClanCtrl.updateById
# .on 'clan.search', authed ClanCtrl.search

.on 'payments.verify', authed PaymentCtrl.verify
.on 'payments.purchase', authed PaymentCtrl.purchase

.on 'connections.upsert', authed ConnectionCtrl.upsert
.on 'connections.upsertByCode', authed ConnectionCtrl.upsertByCode
.on 'connections.getAll', authed ConnectionCtrl.getAll
.on 'connections.giveUpgradesByGroupId',
  authed ConnectionCtrl.giveUpgradesByGroupId

.on 'conversations.create', authed ConversationCtrl.create
.on 'conversations.updateById', authed ConversationCtrl.updateById
.on 'conversations.markReadById', authed ConversationCtrl.markReadById
.on 'conversations.getAll', authed ConversationCtrl.getAll
.on 'conversations.getAllByGroupId', authed ConversationCtrl.getAllByGroupId
.on 'conversations.getById', authed ConversationCtrl.getById

.on 'clashRoyaleAPI.refreshByClanId',
  authed ClashRoyaleAPICtrl.refreshByClanId

.on 'clashRoyaleDecks.getById', authed ClashRoyaleDeckCtrl.getById
.on 'clashRoyaleDecks.getPopular',
  authed ClashRoyaleDeckCtrl.getPopular

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

.on 'notifications.getAll', authed NotificationCtrl.getAll

.on 'nps.create', authed NpsCtrl.create

.on 'iap.getAllByPlatform', authed IapCtrl.getAllByPlatform

.on 'items.getAllByGroupId', authed ItemCtrl.getAllByGroupId

.on 'bans.getAllByGroupId', authed BanCtrl.getAllByGroupId
.on 'bans.getByGroupIdAndUserId', authed BanCtrl.getByGroupIdAndUserId
.on 'bans.banByGroupIdAndIp', authed BanCtrl.banByGroupIdAndIp
.on 'bans.banByGroupIdAndUserId', authed BanCtrl.banByGroupIdAndUserId
.on 'bans.unbanByGroupIdAndUserId', authed BanCtrl.unbanByGroupIdAndUserId

.on 'polls.getById', authed PollCtrl.getById
.on 'polls.getAllByGroupId', authed PollCtrl.getAllByGroupId
.on 'polls.getAllVotesById', authed PollCtrl.getAllVotesById
.on 'polls.resetById', authed PollCtrl.resetById
.on 'polls.voteById', authed PollCtrl.voteById

.on 'products.getAllByGroupId', authed ProductCtrl.getAllByGroupId
.on 'products.buy', authed ProductCtrl.buy

.on 'lfg.getAllByGroupIdAndHashtag', authed LfgCtrl.getAllByGroupIdAndHashtag
.on 'lfg.getByGroupIdAndMe', authed LfgCtrl.getByGroupIdAndMe
.on 'lfg.deleteByGroupIdAndUserId', authed LfgCtrl.deleteByGroupIdAndUserId
.on 'lfg.upsert', authed LfgCtrl.upsert

.on 'rewards.setup', authed RewardCtrl.setup
.on 'rewards.getAll', authed RewardCtrl.getAll
.on 'rewards.incrementAttemptsByNetworkAndOfferId',
  authed RewardCtrl.incrementAttemptsByNetworkAndOfferId

.on 'specialOffer.getAll', authed SpecialOfferCtrl.getAll
.on 'specialOffer.giveDailyReward', authed SpecialOfferCtrl.giveDailyReward
.on 'specialOffer.giveInstallReward', authed SpecialOfferCtrl.giveInstallReward
.on 'specialOffer.logClickById', authed SpecialOfferCtrl.logClickById

.on 'stars.getByUsername', authed StarCtrl.getByUsername
.on 'stars.getAll', authed StarCtrl.getAll

.on 'videos.getAllByGroupId', authed VideoCtrl.getAllByGroupId
.on 'videos.getById', authed VideoCtrl.getById
.on 'videos.logViewById', authed VideoCtrl.logViewById
