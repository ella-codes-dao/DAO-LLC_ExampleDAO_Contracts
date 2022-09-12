import DAOManager from "../DAOManager.cdc"
import FlowToken from "../utility/FlowToken.cdc"
import FiatToken from "../utility/FiatToken.cdc"
import FUSD from "../utility/FUSD.cdc"

transaction(initialSigners: [Address], initialThreshold: UInt) {
  
  prepare(signer: AuthAccount) {
    let dao <- DAOManager.createDAO(initialSigners: initialSigners, initialThreshold: initialThreshold)

    // Seed Treasury with commonly used vaults
    let flowVault <- FlowToken.createEmptyVault()
    let usdcVault <- FiatToken.createEmptyVault()
    let fusdVault <- FUSD.createEmptyVault()

    dao.depositVault(vault: <- flowVault)
    dao.depositVault(vault: <- usdcVault)
    dao.depositVault(vault: <- fusdVault)

    // Save Treasury to the account
    signer.save(<- dao, to: DAOManager.DAOManagerStoragePath)
    signer.link<&DAOManager.DAO{DAOManager.DAOPublic}>(DAOManager.DAOPublicPath, target: DAOManager.DAOStoragePath)
  }
}