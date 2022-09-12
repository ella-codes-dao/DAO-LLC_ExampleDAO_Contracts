import MyMultiSigV4 from "./MyMultiSig.cdc"
import DAOManager from "./DAOManager.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"
import NonFungibleToken from "./utility/NonFungibleToken.cdc"

pub contract DAOActions {

  // Utility
  pub fun InitializeActionView(type: String, intent: String, proposer: Address): MyMultiSigV4.ActionView {
    return MyMultiSigV4.ActionView(
      type: type,
      intent: intent,
      proposer: proposer,
      recipient: nil,
      vaultId: nil,
      collectionId: nil,
      nftId: nil,
      tokenAmount: nil,
      signerAddr: nil,
      newThreshold: nil
    )
  }

  // Transfers `amount` tokens from the dao to `recipientVault`
  pub struct TransferToken: MyMultiSigV4.Action {
    pub let intent: String
    pub let proposer: Address
    pub let recipientVault: Capability<&{FungibleToken.Receiver}>
    pub let amount: UFix64

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO
      let vaultID: String = self.recipientVault.borrow()!.getType().identifier
      let withdrawnTokens <- daoRef.withdrawTokens(identifier: vaultID, amount: self.amount)
      self.recipientVault.borrow()!.deposit(from: <- withdrawnTokens)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "TransferToken",
        intent: self.intent,
        proposer: self.proposer
      )
      view.recipient = self.recipientVault.borrow()!.owner!.address
      view.vaultId = self.recipientVault.borrow()!.getType().identifier
      view.tokenAmount = self.amount
      return view
    }

    init(recipientVault: Capability<&{FungibleToken.Receiver}>, amount: UFix64, proposer: Address) {
      pre {
        amount > 0.0 : "Amount should be higher than 0.0"  
      }

      self.intent = "Transfer "
                        .concat(amount.toString())
                        .concat(" ")
                        .concat(recipientVault.borrow()!.getType().identifier)
                        .concat(" tokens from the dao to ")
                        .concat(recipientVault.borrow()!.owner!.address.toString())
      self.recipientVault = recipientVault
      self.amount = amount
      self.proposer = proposer
    }
  }

  // Transfers `amount` of `identifier` tokens from the dao to another dao
  pub struct TransferTokenToDAO: MyMultiSigV4.Action {
    pub let intent: String
    pub let proposer: Address
    pub let identifier: String
    pub let recipientDAO: Capability<&{DAOManager.DAOPublic}>
    pub let amount: UFix64

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO
      let withdrawnTokens <- daoRef.withdrawTokens(identifier: self.identifier, amount: self.amount)

      let recipientAddr = self.recipientDAO.borrow()!.owner!.address
      self.recipientDAO.borrow()!.depositTokens(identifier: self.identifier, vault: <- withdrawnTokens)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "TransferTokenToDAO",
        intent: self.intent,
        proposer: self.proposer
      )
      view.recipient = self.recipientDAO.borrow()!.owner!.address
      view.vaultId = self.identifier
      view.tokenAmount = self.amount
      return view 
    }

    init(recipientDAO: Capability<&{DAOManager.DAOPublic}>, identifier: String, amount: UFix64, proposer: Address) {
      pre {
        amount > 0.0 : "Amount should be higher than 0.0"  
      }
      
      let recipientAddr = recipientDAO.borrow()!.owner!.address
      self.intent = "Transfer "
                        .concat(amount.toString())
                        .concat(" ")
                        .concat(identifier)
                        .concat(" tokens from the dao to ")
                        .concat(recipientAddr.toString())
      self.proposer = proposer
      self.identifier = identifier
      self.recipientDAO = recipientDAO
      self.amount = amount
    }
  }

  // Transfers an NFT from the dao to `recipientCollection`
  pub struct TransferNFT: MyMultiSigV4.Action {
    pub let intent: String
    pub let proposer: Address
    pub let recipientCollection: Capability<&{NonFungibleToken.CollectionPublic}>
    pub let withdrawID: UInt64

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO
      let collectionID = self.recipientCollection.borrow()!.getType().identifier
      
      let nft <- daoRef.withdrawNFT(identifier: collectionID, id: self.withdrawID)

      self.recipientCollection.borrow()!.deposit(token: <- nft)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "TransferNFT",
        intent: self.intent,
        proposer: self.proposer
      )
      view.recipient = self.recipientCollection.borrow()!.owner!.address
      view.collectionId = self.recipientCollection.borrow()!.getType().identifier
      view.nftId = self.withdrawID
      return view
    }

    init(recipientCollection: Capability<&{NonFungibleToken.CollectionPublic}>, nftID: UInt64, proposer: Address) {
      let recipientAddr = recipientCollection.borrow()!.owner!.address
      let collectionID = recipientCollection.borrow()!.getType().identifier

      self.intent = "Transfer "
                        .concat(collectionID)
                        .concat(" NFT from the dao to ")
                        .concat(recipientAddr.toString())

      self.proposer = proposer
      self.recipientCollection = recipientCollection
      self.withdrawID = nftID
    }
  }

  // Transfers an NFT from the dao to another dao
  pub struct TransferNFTToDAO: MyMultiSigV4.Action {
    pub let intent: String
    pub let proposer: Address
    pub let identifier: String
    pub let recipientDAO: Capability<&{DAOManager.DAOPublic}>
    pub let withdrawID: UInt64

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO
      let nft <- daoRef.withdrawNFT(identifier: self.identifier, id: self.withdrawID)

      let recipientCollectionRef: &{NonFungibleToken.CollectionPublic} = self.recipientDAO.borrow()!.borrowCollectionPublic(identifier: self.identifier)
      recipientCollectionRef.deposit(token: <- nft)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "TransferNFTToDAO",
        intent: self.intent,
        proposer: self.proposer
      )
      view.recipient = self.recipientDAO.borrow()!.owner!.address
      view.collectionId = self.identifier
      view.nftId = self.withdrawID
      return view
    }

    init(recipientDAO: Capability<&{DAOManager.DAOPublic}>, identifier: String, nftID: UInt64, proposer: Address) {
      let recipientAddr = recipientDAO.borrow()!.owner!.address
      self.intent = "Transfer an NFT from collection"
                        .concat(" ")
                        .concat(identifier)
                        .concat(" with ID ")
                        .concat(nftID.toString())
                        .concat(" ")
                        .concat("from this DAO to DAO at address ")
                        .concat(recipientAddr.toString())
      self.identifier = identifier
      self.recipientDAO = recipientDAO
      self.withdrawID = nftID
      self.proposer = proposer
    }
  }

  // Add a new signer to the dao
  pub struct AddSigner: MyMultiSigV4.Action {
    pub let signer: Address
    pub let intent: String
    pub let proposer: Address

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO

      let manager = daoRef.borrowManager()
      manager.addSigner(signer: self.signer)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "AddSigner",
        intent: self.intent,
        proposer: self.proposer
      ) 
      view.signerAddr = self.signer
      return view
    }

    init(signer: Address, proposer: Address) {
      self.proposer = proposer
      self.signer = signer
      self.intent = "Add account "
                      .concat(signer.toString())
                      .concat(" as a signer.")
    }
  }

  // Remove a signer from the dao
  pub struct RemoveSigner: MyMultiSigV4.Action {
    pub let signer: Address
    pub let intent: String
    pub let proposer: Address

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO

      let manager = daoRef.borrowManager()
      manager.removeSigner(signer: self.signer)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "RemoveSigner",
        intent: self.intent,
        proposer: self.proposer
      )
      view.signerAddr = self.signer
      return view
    }

    init(signer: Address, proposer: Address) {
      self.proposer = proposer
      self.signer = signer
      self.intent = "Remove "
                      .concat(signer.toString())
                      .concat(" as a signer.")
    }
  }

  // Update the threshold of signers
  pub struct UpdateThreshold: MyMultiSigV4.Action {
    pub let threshold: UInt
    pub let intent: String
    pub let proposer: Address

    access(account) fun execute(_ params: {String: AnyStruct}) {
      let daoRef: &DAOManager.DAO = params["dao"]! as! &DAOManager.DAO

      let manager = daoRef.borrowManager()
      let oldThreshold = manager.threshold
      manager.updateThreshold(newThreshold: self.threshold)
    }

    pub fun getView(): MyMultiSigV4.ActionView {
      let view: MyMultiSigV4.ActionView = DAOActions.InitializeActionView(
        type: "UpdateThreshold",
        intent: self.intent,
        proposer: self.proposer
      )
      view.newThreshold = self.threshold
      return view
    }

    init(threshold: UInt, proposer: Address) {
      self.threshold = threshold
      self.proposer = proposer
      self.intent = "Update the threshold of signers to ".concat(threshold.toString()).concat(".")
    }
  }
}