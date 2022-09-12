import MyMultiSigV4 from "./MyMultiSig.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"
import NonFungibleToken from "./utility/NonFungibleToken.cdc"
import FCLCrypto from "./utility/FCLCrypto.cdc"

pub contract DAOManager {

  pub let DAOStoragePath: StoragePath
  pub let DAOPublicPath: PublicPath

  // ------- Events ------

  // DAOManager
  pub event DAOInitialized(initialSigners: [Address], initialThreshold: UInt)

  // Actions
  pub event ActionProposed(daoUUID: UInt64, actionUUID: UInt64, proposer: Address, actionView: MyMultiSigV4.ActionView)
  pub event ActionExecuted(daoUUID: UInt64, actionUUID: UInt64, executor: Address, actionView: MyMultiSigV4.ActionView, signerResponses: {Address: UInt})
  pub event ActionDestroyed(daoUUID: UInt64, actionUUID: UInt64, signerResponses: {Address: UInt})
  pub event ActionApprovedBySigner(daoUUID: UInt64, address: Address, actionUUID: UInt64, signerResponses: {Address: UInt})
  pub event ActionRejectedBySigner(daoUUID: UInt64, address: Address, actionUUID: UInt64, signerResponses: {Address: UInt})

  // Vaults
  pub event VaultDeposited(daoUUID: UInt64, signerAddr: Address, vaultID: String)
  pub event VaultDestroyed(daoUUID: UInt64, signerAddr: Address, vaultID: String)

  // Collections
  pub event CollectionDeposited(daoUUID: UInt64, signerAddr: Address, collectionID: String)
  pub event CollectionDestroyed(daoUUID: UInt64, signerAddr: Address, collectionID: String)

  // Tokens
  pub event TokensDeposited(daoUUID: UInt64, identifier: String)

  // NFTs
  pub event NFTDeposited(daoUUID: UInt64, collectionID: String, nftID: UInt64)

  //
  // ------- Interfaces + Resources -------
  //
  pub resource interface DAOPublic {
    pub fun signerApproveAction(actionUUID: UInt64, messageSignaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun signerRejectAction(actionUUID: UInt64, messageSignaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun proposeAction(action: {MyMultiSigV4.Action}, signaturePayload: MyMultiSigV4.MessageSignaturePayload): UInt64
    pub fun executeAction(actionUUID: UInt64, signaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun signerDepositCollection(collection: @NonFungibleToken.Collection, signaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun signerRemoveCollection(identifier: String, signaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun signerDepositVault(vault: @FungibleToken.Vault, signaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun signerRemoveVault(identifier: String, signaturePayload: MyMultiSigV4.MessageSignaturePayload)
    pub fun depositTokens(identifier: String, vault: @FungibleToken.Vault)
    pub fun depositNFT(identifier: String, nft: @NonFungibleToken.NFT)
    pub fun borrowManagerPublic(): &MyMultiSigV4.Manager{MyMultiSigV4.ManagerPublic}
    pub fun borrowVaultPublic(identifier: String): &{FungibleToken.Balance}
    pub fun borrowCollectionPublic(identifier: String): &{NonFungibleToken.CollectionPublic}
    pub fun getVaultIdentifiers(): [String]
    pub fun getCollectionIdentifiers(): [String]
  }

  pub resource DAO: MyMultiSigV4.MultiSign, DAOPublic {
    access(contract) let multiSignManager: @MyMultiSigV4.Manager
    access(self) var vaults: @{String: FungibleToken.Vault}
    access(self) var collections: @{String: NonFungibleToken.Collection}

    pub fun signerApproveAction(actionUUID: UInt64, messageSignaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      self.multiSignManager.signerApproveAction(actionUUID: actionUUID, messageSignaturePayload: messageSignaturePayload) 
      let signerResponses = self.multiSignManager.getSignerResponsesForAction(actionUUID: actionUUID)
      emit ActionApprovedBySigner(daoUUID: self.uuid, address: messageSignaturePayload.signingAddr, actionUUID: actionUUID, signerResponses: signerResponses)
    }

    pub fun signerRejectAction(actionUUID: UInt64, messageSignaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      self.multiSignManager.signerRejectAction(actionUUID: actionUUID, messageSignaturePayload: messageSignaturePayload) 
      let signerResponses = self.multiSignManager.getSignerResponsesForAction(actionUUID: actionUUID)
      emit ActionRejectedBySigner(daoUUID: self.uuid, address: messageSignaturePayload.signingAddr, actionUUID: actionUUID, signerResponses: signerResponses)

      // Destroy action if there are sufficient rejections
      if self.multiSignManager.canDestroyAction(actionUUID: actionUUID) {
         self.multiSignManager.attemptDestroyAction(actionUUID: actionUUID)
         emit ActionDestroyed(daoUUID: self.uuid, actionUUID: actionUUID, signerResponses: signerResponses)
      }
    }

    pub fun proposeAction(action: {MyMultiSigV4.Action}, signaturePayload: MyMultiSigV4.MessageSignaturePayload): UInt64 {
      self.validateTreasurySigner(identifier: action.intent, signaturePayload: signaturePayload)

      let actionUUID = self.multiSignManager.createMultiSign(action: action)
      let _action = self.multiSignManager.borrowAction(actionUUID: actionUUID)
      let actionView = _action.getView()
      emit ActionProposed(daoUUID: self.uuid, actionUUID: actionUUID, proposer: actionView.proposer, actionView: actionView)
      return actionUUID
    }

    /*
      Note that we pass through a reference to this entire
      dao as a parameter here. So the action can do whatever it 
      wants. This means it's very imporant for the signers
      to know what they are signing.
    */
    pub fun executeAction(actionUUID: UInt64, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      self.validateTreasurySigner(identifier: actionUUID.toString(), signaturePayload: signaturePayload)

      let action = self.multiSignManager.borrowAction(actionUUID: actionUUID)
      let actionView = action.getView()
      let selfRef: &DAO = &self as &DAO
      let signerResponses = self.multiSignManager.getSignerResponsesForAction(actionUUID: actionUUID)
      self.multiSignManager.executeAction(actionUUID: actionUUID, {"dao": selfRef})
      emit ActionExecuted(
        daoUUID: self.uuid,
        actionUUID: actionUUID,
        executor: signaturePayload.signingAddr,
        actionView: actionView,
        signerResponses: signerResponses
      )
    }

    access(self) fun validateTreasurySigner(identifier: String, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      // ------- Validate Address is a Signer on the DAO -----
      let signers = self.multiSignManager.getSigners()
      assert(signers[signaturePayload.signingAddr] == true, message: "Address is not a signer on this DAO")

      // ------- Validate Message --------
      // message format: {identifier hex}{blockId}
      let message = signaturePayload.message

      // ------- Validate Identifier -------
      let identifierHex = String.encodeHex(identifier.utf8)
      assert(
        identifierHex == message.slice(from: 0, upTo: identifierHex.length),
        message: "Invalid Message: incorrect identifier"
      )

      // ------ Validate Block ID --------
      MyMultiSigV4.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: identifierHex.length, upTo: message.length))

      // ------ Validate Signature -------
      let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
        address: signaturePayload.signingAddr,
        message: String.encodeHex(signaturePayload.message.utf8),
        keyIndices: signaturePayload.keyIds,
        signatures: signaturePayload.signatures
      )
      assert(
        signatureValidationResponse == true,
        message: "Invalid Signature"
      )
    }

    // Reference to Manager //
    access(account) fun borrowManager(): &MyMultiSigV4.Manager {
      return &self.multiSignManager as &MyMultiSigV4.Manager
    }

    pub fun borrowManagerPublic(): &MyMultiSigV4.Manager{MyMultiSigV4.ManagerPublic} {
      return &self.multiSignManager as &MyMultiSigV4.Manager{MyMultiSigV4.ManagerPublic}
    }

    // ------- Vaults ------- 

    pub fun signerRemoveVault(identifier: String, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      pre {
        self.vaults[identifier] != nil: "Vault doesn't exist in this dao."
        self.vaults[identifier]?.balance == 0.0: "Vault must be empty before it can be removed."
      }
      // ------- Validate Address is a Signer on the DAO -----
      let signers = self.multiSignManager.getSigners()
      assert(signers[signaturePayload.signingAddr] == true, message: "Address is not a signer on this DAO")

      // ------- Validate Message --------
      // message format: {collection identifier hex}{blockId}
      let message = signaturePayload.message

      // ----- Validate Vault Identifier -----
      let vaultIdHex = String.encodeHex(identifier.utf8)
      assert(
        vaultIdHex == message.slice(from: 0, upTo: vaultIdHex.length),
        message: "Invalid Message: incorrect vault identifier"
      )

      // ------ Validate Block ID --------
      MyMultiSigV4.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: vaultIdHex.length, upTo: message.length))

      // ------ Validate Signature -------
      let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
          address: signaturePayload.signingAddr,
          message: String.encodeHex(signaturePayload.message.utf8),
          keyIndices: signaturePayload.keyIds,
          signatures: signaturePayload.signatures
      )
      assert(
        signatureValidationResponse == true,
        message: "Invalid Signature"
      )

      // If all asserts passed, remove vault from the DAO and destroy
      let vault <- self.vaults.remove(key: identifier)
      destroy vault
      emit VaultDestroyed(daoUUID: self.uuid, signerAddr: signaturePayload.signingAddr, vaultID: identifier)
    }

    // Deposit a Vault //
    pub fun depositVault(vault: @FungibleToken.Vault) {
      let identifier = vault.getType().identifier
      if self.vaults[identifier] != nil {
        self.vaults[identifier]?.deposit!(from: <- vault)
      } else {
        self.vaults[identifier] <-! vault
      }
    }

    // Withdraw some tokens //
    access(account) fun withdrawTokens(identifier: String, amount: UFix64): @FungibleToken.Vault {
      let vaultRef = (&self.vaults[identifier] as &FungibleToken.Vault?)!
      return <- vaultRef.withdraw(amount: amount)
    }

    // Public Reference to Vault //
    pub fun borrowVaultPublic(identifier: String): &{FungibleToken.Balance} {
      return (&self.vaults[identifier] as &{FungibleToken.Balance}?)!
    }

    pub fun getVaultIdentifiers(): [String] {
      return self.vaults.keys
    }


    // ------- Collections ------- 

    pub fun signerDepositCollection(collection: @NonFungibleToken.Collection, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      // ------- Validate Address is a Signer on the DAO -----
      let signers = self.multiSignManager.getSigners()
      assert(signers[signaturePayload.signingAddr] == true, message: "Address is not a signer on this DAO")

      // ------- Validate Message --------
      // message format: {collection identifier hex}{blockId}
      let message = signaturePayload.message

      // ------- Validate Collection Identifier -------
      let identifier = collection.getType().identifier
      let collectionIdHex = String.encodeHex(identifier.utf8)
      assert(
        collectionIdHex == message.slice(from: 0, upTo: collectionIdHex.length),
        message: "Invalid Message: incorrect collection identifier"
      )

      // ------ Validate Block ID --------
      MyMultiSigV4.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: collectionIdHex.length, upTo: message.length))

      // ------ Validate Signature -------
      let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
          address: signaturePayload.signingAddr,
          message: String.encodeHex(signaturePayload.message.utf8),
          keyIndices: signaturePayload.keyIds,
          signatures: signaturePayload.signatures
      )
      assert(
        signatureValidationResponse == true,
        message: "Invalid Signature"
      )

      // If all asserts passed, deposit vault into DAO
      self.depositCollection(collection: <- collection)
      emit CollectionDeposited(daoUUID: self.uuid, signerAddr: signaturePayload.signingAddr, collectionID: identifier)
    }

    pub fun signerRemoveCollection(identifier: String, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      pre {
        self.collections[identifier] != nil: "Collection doesn't exist in this dao."
        self.collections[identifier]?.getIDs()?.length == 0 : "Collection must be empty before it can be removed."
      }
      // ------- Validate Address is a Signer on the DAO -----
      let signers = self.multiSignManager.getSigners()
      assert(signers[signaturePayload.signingAddr] == true, message: "Address is not a signer on this DAO")

      // ------- Validate Message --------
      // message format: {collection identifier hex}{blockId}

      let collectionIdHex = String.encodeHex(identifier.utf8)
      let message = signaturePayload.message

      // ------ Validate Collection Identifier ------
      assert(
        collectionIdHex == message.slice(from: 0, upTo: collectionIdHex.length),
        message: "Invalid Message: incorrect collection identifier"
      )

      // ------ Validate Block ID --------
      MyMultiSigV4.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: collectionIdHex.length, upTo: message.length))

      // ------ Validate Signature -------
      let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
        address: signaturePayload.signingAddr,
        message: String.encodeHex(signaturePayload.message.utf8),
        keyIndices: signaturePayload.keyIds,
        signatures: signaturePayload.signatures
      )
      assert(
        signatureValidationResponse == true,
        message: "Invalid Signature"
      )

      // If all asserts passed, remove vault from the DAO and destroy
      let collection <- self.collections.remove(key: identifier)
      destroy collection
      emit CollectionDestroyed(daoUUID: self.uuid, signerAddr: signaturePayload.signingAddr, collectionID: identifier)
    }

    // Deposit a Collection //
    pub fun depositCollection(collection: @NonFungibleToken.Collection) {
      let identifier = collection.getType().identifier
      self.collections[identifier] <-! collection
    }

    // ------- Vaults ------- 
    pub fun signerDepositVault(vault: @FungibleToken.Vault, signaturePayload: MyMultiSigV4.MessageSignaturePayload) {
      // ------- Validate Address is a Signer on the DAO -----
      let signers = self.multiSignManager.getSigners()
      assert(signers[signaturePayload.signingAddr] == true, message: "Address is not a signer on this DAO")

      // ------- Validate Message --------
      // message format: {vault identifier hex}{blockId}
      
      let identifier = vault.getType().identifier
      let vaultIdHex = String.encodeHex(identifier.utf8)

      let message = signaturePayload.message

      // Vault Identifier
      assert(
        vaultIdHex == message.slice(from: 0, upTo: vaultIdHex.length),
        message: "Invalid Message: incorrect vault identifier"
      )

      // ------ Validate Block ID --------
      MyMultiSigV4.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: vaultIdHex.length, upTo: message.length))

      // ------ Validate Signature -------
      let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
        address: signaturePayload.signingAddr,
        message: String.encodeHex(signaturePayload.message.utf8),
        keyIndices: signaturePayload.keyIds,
        signatures: signaturePayload.signatures
      )
      assert(
        signatureValidationResponse == true,
        message: "Invalid Signature"
      )

      // If all asserts passed, deposit vault into DAO
      self.depositVault(vault: <- vault)
      emit VaultDeposited(daoUUID: self.uuid, signerAddr: signaturePayload.signingAddr, vaultID: identifier)
    }

    // Deposit tokens //
    pub fun depositTokens(identifier: String, vault: @FungibleToken.Vault) {
      emit TokensDeposited(daoUUID: self.uuid, identifier: identifier)

      let vaultRef = (&self.vaults[identifier] as &FungibleToken.Vault?)!
      vaultRef.deposit(from: <- vault)
    }


    // Deposit an NFT //
    pub fun depositNFT(identifier: String, nft: @NonFungibleToken.NFT) {
      emit NFTDeposited(daoUUID: self.uuid, collectionID: identifier, nftID: nft.id)

      let collectionRef = (&self.collections[identifier] as &NonFungibleToken.Collection?)!
      collectionRef.deposit(token: <- nft)
    }

    // Withdraw an NFT //
    access(account) fun withdrawNFT(identifier: String, id: UInt64): @NonFungibleToken.NFT {
      let collectionRef = (&self.collections[identifier] as &NonFungibleToken.Collection?)!
      return <- collectionRef.withdraw(withdrawID: id)
    }

    // Public Reference to Collection //
    pub fun borrowCollectionPublic(identifier: String): &{NonFungibleToken.CollectionPublic} {
      return (&self.collections[identifier] as &{NonFungibleToken.CollectionPublic}?)!
    }

     pub fun getCollectionIdentifiers(): [String] {
      return self.collections.keys
    }

    init(initialSigners: [Address], initialThreshold: UInt) {
      self.multiSignManager <- MyMultiSigV4.createMultiSigManager(signers: initialSigners, threshold: initialThreshold)
      self.vaults <- {}
      self.collections <- {}
    }

    destroy() {
      // Check if Valuts are empty
      for identifier in self.vaults.keys {
        let vaultRef = (&self.vaults[identifier] as &FungibleToken.Vault?)!
        assert(vaultRef.balance == 0.0, message: "Vault is not empty! DAO cannot be destroyed.")
      }

      // Check if Collections are empty
      for identifier in self.collections.keys {
        let collectionRef = (&self.collections[identifier] as &NonFungibleToken.Collection?)!
        assert(collectionRef.getIDs().length == 0, message: "Collection is not empty! DAO cannot be destroyed.")
      }

      // Only destroy if both vaults and collections are empty
      destroy self.multiSignManager
      destroy self.vaults
      destroy self.collections
    }
  }
  
  pub fun createDAO(initialSigners: [Address], initialThreshold: UInt): @DAO {
    return <- create DAO(initialSigners: initialSigners, initialThreshold: initialThreshold)
  }

  init() {
    self.DAOStoragePath = /storage/DAOManager
    self.DAOPublicPath = /public/DAOManager
  }

}