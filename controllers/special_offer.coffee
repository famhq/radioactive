_ = require 'lodash'

SpecialOffer = require '../models/special_offer'

class SpecialOfferCtrl
  getAll: ({}, {user}) ->
    SpecialOffer.getAll()
    .then (offers) ->
      offerIds = _.map offers, 'id'
      console.log 'off', offerIds
      SpecialOffer.getAllTransactionsByUserIdAndOfferIds user.id, offerIds
      .then (transactions) ->
        console.log 'transactions', transactions

        offers


  giveReward: ({offerId, usageStats}, {user}) ->
    console.log 'give reward'
    SpecialOffer.getTransactionByUserIdAndOfferId user.id, offerId
    .then (transaction) ->
      SpecialOffer.createTransaction {
        offerId: offerId
        userId: user.id
        status: 'active'
        # track x number of days, y fire per days
        startTime: new Date()
        days: []
        fireEarned: 0
      }

module.exports = new SpecialOfferCtrl()
