_ = require 'lodash'
router = require 'exoid-router'
Promise = require 'bluebird'
moment = require 'moment'

GroupPage = require '../models/group_page'
GroupAuditLog = require '../models/group_audit_log'
GroupUser = require '../models/group_user'
Group = require '../models/group'
Language = require '../models/language'

class GroupPageCtrl
  upsert: ({groupId, title, body, key}, {user}) ->
    GroupUser.hasPermissionByGroupIdAndUser groupId, user, [
      GroupUser.PERMISSIONS.MANAGE_PAGE
    ]
    .then (hasPermission) ->
      unless hasPermission
        router.throw status: 400, info: 'no permission'

      GroupAuditLog.upsert {
        groupId: groupId
        userId: user.id
        actionText: Language.get 'audit.editPage', {
          replacements:
            key: key
          language: user.language
        }
      }

    unless key
      router.throw {status: '401', info: 'needs a key'}

    GroupPage.upsert {
      groupId, key
      data:
        title: title
        body: body
    }

  getAllByGroupId: ({groupId}, {user}) ->
    GroupPage.getAllByGroupId groupId
    .map (groupPage) ->
      groupPage.data = _.pick groupPage.data, ['title']
      groupPage

  getByGroupIdAndKey: ({groupId, key}, {user}) ->
    GroupPage.getByGroupIdAndKey groupId, key

module.exports = new GroupPageCtrl()
