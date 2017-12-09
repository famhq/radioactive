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


  giveReward: ({}, {user}) ->
    console.log 'give reward'
    null

module.exports = new SpecialOfferCtrl()
