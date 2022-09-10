import ExampleDaoToken from "./ExampleDaoToken.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"

pub contract AdminActions {

  ///////////
  // Events
  ///////////

  // Mint Token
  pub event MintTokenToAccountActionCreated(recipientAddr: Address, amount: UFix64)
  pub event MintTokenToAccountActionExecuted(recipientAddr: Address, amount: UFix64)

  // Update Threshold
  pub event UpdateThresholdActionCreated(threshold: UFix64)
  pub event UpdateThresholdActionExecuted(oldThreshold: UFix64, newThreshold: UFix64)

  // Mints `amount` of tokens to `recipientVault`
  pub struct MintToken: ExampleDaoToken.Action {
    pub let intent: String
    pub let proposer: Address
    pub let recipientVault: Capability<&{FungibleToken.Receiver}>
    pub let amount: UFix64

    access(account) fun execute(_ adminRef: &ExampleDaoToken.Admin) {
      let mintedTokens <- adminRef.mintTokens(amount: self.amount)
      self.recipientVault.borrow()!.deposit(from: <- mintedTokens)

      emit MintTokenToAccountActionExecuted(
        recipientAddr: self.recipientVault.borrow()!.owner!.address,
        amount: self.amount
      )
    }

    init(recipientVault: Capability<&{FungibleToken.Receiver}>, amount: UFix64, proposer: Address) {
      pre {
        amount > 0.0 : "Amount should be higher than 0.0"  
      }

      self.intent = "Mint "
                        .concat(amount.toString())
                        .concat(" ")
                        .concat(" tokens to ")
                        .concat(recipientVault.borrow()!.owner!.address.toString())
      self.recipientVault = recipientVault
      self.amount = amount
      self.proposer = proposer

      emit MintTokenToAccountActionCreated(
        recipientAddr: recipientVault.borrow()!.owner!.address,
        amount: amount
      )
    }
  }

  // Update the threshold of signers
  pub struct UpdateThreshold: ExampleDaoToken.Action {
    pub let threshold: UFix64
    pub let intent: String
    pub let proposer: Address

    access(account) fun execute(_ adminRef: &ExampleDaoToken.Admin) {
      let oldThreshold = ExampleDaoToken.threshold
      adminRef.updateThreshold(self.threshold)
      emit UpdateThresholdActionExecuted(oldThreshold: oldThreshold, newThreshold: self.threshold)
    }

    init(threshold: UFix64, proposer: Address) {
      self.threshold = threshold
      self.proposer = proposer
      self.intent = "Update the threshold of signers to ".concat(threshold.toString()).concat(".")
      emit UpdateThresholdActionCreated(threshold: threshold)
    }
  }
}