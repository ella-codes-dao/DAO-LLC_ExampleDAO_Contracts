import Crypto
import FCLCrypto from "./utility/FCLCrypto.cdc"
import FungibleToken from "./utility/FungibleToken.cdc"
import ExampleDAOToken from "./ExampleDAOToken.cdc"

pub contract DAOVoteManager {
    // ------- Struct Interfaces -------- //

    // VoteAction
    //
    // Each action that could be voted on must implement the VoteAction interface
    //
    pub struct interface VoteAction {
        pub let intent: String
        pub let proposer: Address
        access(account) fun execute()
    }

    // ------- Structs -------- //

    // MessageSignaturePayload
    //
    // Struct to wrap a signature payload for each signers vote.
    //
    pub struct MessageSignaturePayload {
        pub let signingAddr: Address
        pub let message: String
        pub let keyIds: [Int]
        pub let signatures: [String]
        pub let signatureBlock: UInt64

        init(signingAddr: Address, message: String, keyIds: [Int], signatures: [String], signatureBlock: UInt64) {
            self.signingAddr = signingAddr
            self.message = message
            self.keyIds = keyIds
            self.signatures = signatures
            self.signatureBlock = signatureBlock
        }
    }

    // ValidateSignatureResponse
    //
    // Struct to wrap the signature validation response.
    //
    pub struct ValidateSignatureResponse {
        pub let isValid: Bool
        pub let totalWeight: UFix64

        init(isValid: Bool, totalWeight: UFix64) {
            self.isValid = isValid
            self.totalWeight = totalWeight
        }
    }

    // ------- Enums------- //

    // SignerResponse
    //
    // Enum to wrap the signer response to a VoteAction
    //
    pub enum SignerResponse: UInt {
        pub case approved
        pub case rejected
        pub case pending
    }

    // Stage
    //
    // Enum to wrap the current stage of a VoteAction
    //
    pub enum Stage: UInt8 {
        pub case notStarted
        pub case pending
        pub case ended
    }

    // ------- Resource Interfaces ------- //

    // VoteManager Interface
    //
    // To utilize the DAOVoteManager in your DAO Contracts ensure they conform to the following interfaces.
    //
    pub resource interface VoteManager {
        access(contract) let voteManager: @Manager
    }

    pub resource interface VoteManagerPublic {
        pub fun proposeAction(action: {VoteAction}, signaturePayload: MessageSignaturePayload): UInt64
        pub fun getIDs(): [UInt64]
        pub fun getIntents(): {UInt64: String}
        pub fun getSignerResponsesForAction(actionUUID: UInt64): {Address: UInt}
        pub fun getTotalApprovedForAction(actionUUID: UInt64): UFix64
        pub fun getTotalRejectedForAction(actionUUID: UInt64): UFix64
        pub fun vote(actionUUID: UInt64, messageSignaturePayload: MessageSignaturePayload, signerResponse: SignerResponse)
    }

    pub resource interface ManagerPublic {
        pub fun borrowAction(actionUUID: UInt64): &MultiSignAction
        pub fun getIDs(): [UInt64]
        pub fun getIntents(): {UInt64: String}
        pub fun getSigners(): {Address: Bool}
        pub fun getThreshold(): UInt
        pub fun getSignerResponsesForAction(actionUUID: UInt64): {Address: UInt}
        pub fun getTotalApprovedForAction(actionUUID: UInt64): Int
        pub fun getTotalRejectedForAction(actionUUID: UInt64): Int
    }

    // ------- Resources ------- //

    pub resource VotingAction {
        pub var startTime: UFix64
        pub var endTime: UFix64
        pub var signerResponses: {Address: SignerResponse}
        pub var totalVoted: UFix64
        pub var totalApproved: UFix64
        pub var totalRejected: UFix64
        access(contract) let action: {VoteAction}

        access(contract) fun setSignerResponse(signer: Address, value: SignerResponse) {
            let vaultRef = getAccount(signer)
                                                                                .getCapability(ExampleDAOToken.VaultBalancePath)
                                                                                .borrow<&ExampleDAOToken.Vault{FungibleToken.Balance}>()
                                                                                ?? panic("Could not borrow Balance reference to the Vault")
            self.totalVoted = vaultRef.balance
            if value == SignerResponse.approved {
                self.totalApproved = vaultRef.balance
            } else if value == SignerResponse.rejected {
                self.totalRejected = vaultRef.balance
            }
            self.signerResponses[signer] = value
        }

        init(signers: [Address], action: {VoteAction}) {
            let timestamp = getCurrentBlock().timestamp

            self.signerResponses = {}
            self.action = action
            self.startTime = timestamp
            self.endTime = timestamp + ExampleDAOToken.votingWindow
            self.totalVoted = 0.0
            self.totalApproved = 0.0
            self.totalRejected = 0.0
        }
    }

    // Admin
    //
    // Resource object for administering Voting Actions and minting/burning Example Token.
    //
    pub resource Manager: VoteManagerPublic {
        // Maps the `uuid` of the VotingAction
        // to the resource itself
        access(self) var actions: @{UInt64: VotingAction}

        // ------- Manager -------   
        pub fun proposeAction(action: {VoteAction}, signaturePayload: MessageSignaturePayload): UInt64 {
            self.validateTreasurySigner(identifier: action.intent, signaturePayload: signaturePayload)

            let uuid = self.createVotingAction(action: action)
            emit ProposeAction(actionUUID: uuid, proposer: action.proposer)
            return uuid
        }

        access(self) fun executeAction(actionUUID: UInt64) {
            let action = self.borrowAction(actionUUID: actionUUID)

            let selfRef: &Admin = &self as &Admin
            action.action.execute(selfRef)
            emit ActionExecutedByManager(uuid: actionUUID)
        }

        access(self) fun createVotingAction(action: {VoteAction}): UInt64 {
            let newAction <- create VotingAction(signers: ExampleDAOToken.currentHolders.keys, action: action)
            let uuid = newAction.uuid
            self.actions[newAction.uuid] <-! newAction
            emit ActionCreated(uuid: uuid, intent: action.intent)
            return uuid
        }

        pub fun vote(actionUUID: UInt64, messageSignaturePayload: MessageSignaturePayload, signerResponse: SignerResponse) {
            pre {
                ExampleDAOToken.currentHolders[messageSignaturePayload.signingAddr] == true:
                    "This address is not a current holder of ExampleDAOToken"
                self.actions[actionUUID] != nil: "Couldn't find action with UUID ".concat(actionUUID.toString())
                getCurrentBlock().timestamp >= self.borrowAction(actionUUID: actionUUID).startTime:
                    "It is too early to start voting on this action"
                getCurrentBlock().timestamp <= self.borrowAction(actionUUID: actionUUID).endTime:
                    "Voting has ended on this action"
                self.borrowAction(actionUUID:actionUUID).signerResponses[messageSignaturePayload.signingAddr] == SignerResponse.approved:
                    "This address has already signed."
                self.borrowAction(actionUUID:actionUUID).signerResponses[messageSignaturePayload.signingAddr] == SignerResponse.rejected:
                    "This address has already signed."
            }
            let action = self.borrowAction(actionUUID:actionUUID)

            // Validate Message
            assert(
                ExampleDAOToken.approveOrRejectActionMessageIsValid(action: action, messageSignaturePayload: messageSignaturePayload),
                message: "Signed message is invalid"
            )
        
            // Validate Signature
            let signatureValidationResponse = FCLCrypto.verifyUserSignatures(
                address: messageSignaturePayload.signingAddr,
                message: String.encodeHex(messageSignaturePayload.message.utf8),
                keyIndices: messageSignaturePayload.keyIds,
                signatures: messageSignaturePayload.signatures
            )

            assert(signatureValidationResponse == true, message: "Invalid Signatures")

            // Approve action
            action.setSignerResponse(signer: messageSignaturePayload.signingAddr, value: signerResponse)

            emit ActionApprovedBySigner(address: messageSignaturePayload.signingAddr, uuid: self.uuid)

            if self.readyToExecute(actionUUID: actionUUID) {
                self.executeAction(actionUUID: actionUUID)
            }
        }

        access(self) fun readyToExecute(actionUUID: UInt64): Bool {
            let actionRef: &VotingAction = (&self.actions[actionUUID] as &VotingAction?)!

            return self.votingHasEnded(actionUUID: actionUUID) && 
                    self.voteMeetsQuorum(actionUUID: actionUUID) && 
                    self.voteMeetsThreshold(actionUUID: actionUUID)
        }

        access(self) fun votingHasEnded(actionUUID: UInt64): Bool {
            return self.getTotalVotedForAction(actionUUID: actionUUID) == ExampleDAOToken.totalSupply || 
                    getCurrentBlock().timestamp <= self.borrowAction(actionUUID: actionUUID).endTime
        }

        access(self) fun voteMeetsThreshold(actionUUID: UInt64): Bool {
            return ExampleDAOToken.threshold <= self.getTotalApprovedForAction(actionUUID: actionUUID) / ExampleDAOToken.totalSupply * 100.0
        }

        access(self) fun voteMeetsQuorum(actionUUID: UInt64): Bool {
            return ExampleDAOToken.quorum <= self.getTotalVotedForAction(actionUUID: actionUUID)  / ExampleDAOToken.totalSupply * 100.0
        }

        access(self) fun borrowAction(actionUUID: UInt64): &VotingAction {
            return (&self.actions[actionUUID] as &VotingAction?)!
        }

        pub fun getIDs(): [UInt64] {
            return self.actions.keys
        }

        pub fun getIntents(): {UInt64: String} {
            let returnVal: {UInt64: String} = {}
            for id in self.actions.keys {
                returnVal[id] = self.borrowAction(actionUUID: id).action.intent
            }
            return returnVal
        }

        pub fun getSignerResponsesForAction(actionUUID: UInt64): {Address: UInt} {
            let allResponses: {Address: UInt} = {}
            let responses = self.borrowAction(actionUUID: actionUUID).signerResponses
            for signer in ExampleDAOToken.currentHolders.keys {
                if responses[signer] != nil {
                    allResponses[signer] = responses[signer]!.rawValue
                }
                else {
                    allResponses[signer] = SignerResponse.pending.rawValue
                }
            }
            return  allResponses
        }

        pub fun getTotalVotedForAction(actionUUID: UInt64): UFix64 {
            let action = self.borrowAction(actionUUID: actionUUID)
            return action.totalVoted
        }

        pub fun getTotalApprovedForAction(actionUUID: UInt64): UFix64 {
            let action = self.borrowAction(actionUUID: actionUUID)
            return action.totalApproved
        }

        pub fun getTotalRejectedForAction(actionUUID: UInt64): UFix64 {
            let action = self.borrowAction(actionUUID: actionUUID)
            return action.totalRejected
        }

        access(self) fun validateTreasurySigner(identifier: String, signaturePayload: MessageSignaturePayload) {
            // ------- Validate Address is a Signer on the Treasury -----
            assert(ExampleDAOToken.currentHolders[signaturePayload.signingAddr] == true, message: "Not a current holder of ExampleDAOToken")

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
            ExampleDAOToken.validateMessageBlockId(blockHeight: signaturePayload.signatureBlock, messageBlockId: message.slice(from: identifierHex.length, upTo: message.length))

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

        // mintTokens
        //
        // Function that mints new tokens, adds them to the total supply,
        // and returns them to the calling context.
        //
        access(account) fun mintTokens(amount: UFix64): @ExampleDAOToken.Vault {
            pre {
                amount > 0.0: "Amount minted must be greater than zero"
            }
            ExampleDAOToken.totalSupply = ExampleDAOToken.totalSupply + amount
            emit TokensMinted(amount: amount)
            return <- create Vault(balance: amount)
        }

        access(account) fun updateThreshold(_ newThreshold: UFix64) {
            pre {
                newThreshold > 0.0: "Amount minted must be greater than zero"
            }

            ExampleDAOToken.threshold = newThreshold
        }

        init() {
            self.actions <- {}
        }

        destroy() {
            destroy self.actions
        }
    }

    // Validate the approve/reject approval message
    access(contract) fun approveOrRejectActionMessageIsValid(action: &VotingAction, messageSignaturePayload: MessageSignaturePayload): Bool {
        let signingBlock = getBlock(at: messageSignaturePayload.signatureBlock)!
        assert(signingBlock != nil, message: "Invalid blockId specified for signature block")
        let blockId = signingBlock.id
        let blockIds: [UInt8] = []
        
        for id in blockId {
            blockIds.append(id)
        }

        // message: {uuid of this resource}{intent}{blockId}
        let uuidString = action.uuid.toString()
        let intentHex = String.encodeHex(action.action.intent.utf8)
        let blockIdHexStr: String = String.encodeHex(blockIds)

        // Matches the `uuid` of this resource
        let message = messageSignaturePayload.message
        assert(
            uuidString == message.slice(from: 0, upTo: uuidString.length), 
            message: "This signature is not for this action"
        )
        // Matches the `intent` of this resource
        assert(
            intentHex == message.slice(from: uuidString.length, upTo: uuidString.length + intentHex.length), 
            message: "Failed to validate intent"
        )
        // Ensure that the message passed in is of the current block id...
        assert(
            blockIdHexStr == message.slice(from: uuidString.length + intentHex.length, upTo: message.length), 
            message: "Unable to validate signature provided contained a valid block id."
        )
        return true
    }

    // takes a blockheight included in the signaturePayload and validates that
    // it matches the blockId encoded in the message.
    access(contract) fun validateMessageBlockId(blockHeight: UInt64, messageBlockId: String) {
        var counter = 0
        let signingBlock = getBlock(at: blockHeight)!
        let blockId = signingBlock.id
        let blockIds: [UInt8] = []

        while (counter < blockId.length) {
            blockIds.append(blockId[counter])
            counter = counter + 1
        }

        let blockIdHex = String.encodeHex(blockIds)
        assert(
            blockIdHex == messageBlockId,
            message: "Invalid Message: invalid blockId"
        )
    }
}
 