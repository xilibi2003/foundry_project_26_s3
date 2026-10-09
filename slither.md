'forge clean' running (wd: /Users/emmett/openspace_code/bootcamp_2026_s3/forge_project)
'forge config --json' running
'forge build --build-info --skip ./test/** ./script/** --force' running (wd: /Users/emmett/openspace_code/bootcamp_2026_s3/forge_project)
INFO:Detectors:
Detector: uninitialized-state
MyWallet.approved (src/MyWallet.sol#8) is never initialized. It is used in:
	- MyWallet.printAllSlots() (src/MyWallet.sol#59-70)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#uninitialized-state-variables
INFO:Detectors:
Detector: events-access
MyWallet.transferOwernship(address) (src/MyWallet.sol#29-42) should emit an event for: 
	- sstore(uint256,uint256)(owner,_addr) (src/MyWallet.sol#40) 
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#missing-events-access-control
INFO:Detectors:
Detector: missing-zero-check
MemeToken.initialize(string,string,uint256,uint256,address).factory_ (src/MemeToken.sol#43) lacks a zero-check on :
		- factory = factory_ (src/MemeToken.sol#49)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#missing-zero-address-validation
INFO:Detectors:
Detector: calls-loop
AirdopMerkleNFTMarket.multicall(bytes[]) (src/AirdopMerkleNFTMarket.sol#257-273) has external calls inside a loop: (success,result) = address(this).delegatecall(data[i]) (src/AirdopMerkleNFTMarket.sol#260)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation/#calls-inside-a-loop
INFO:Detectors:
Detector: reentrancy-benign
Reentrancy in MemeFactory.deployMeme(string,uint256,uint256) (src/MemeFactory.sol#58-89):
	External calls:
	- MemeToken(tokenAddr).initialize(symbol,symbol,totalSupply,perMint,address(this)) (src/MemeFactory.sol#77-83)
	State variables written after the call(s):
	- allMemes.push(tokenAddr) (src/MemeFactory.sol#86)
	- isMeme[tokenAddr] = true (src/MemeFactory.sol#85)
Reentrancy in TokenBank.depositWithPermit2(address,ISignatureTransfer.PermitTransferFrom,bytes) (src/TokenBank.sol#173-208):
	External calls:
	- ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature) (src/TokenBank.sol#196-201)
	State variables written after the call(s):
	- balances[owner] += permit.permitted.amount (src/TokenBank.sol#204)
	- _updateTopDepositors(owner) (src/TokenBank.sol#205)
		- listSize -- (src/TokenBank.sol#438)
		- listSize ++ (src/TokenBank.sol#472)
		- listSize -- (src/TokenBank.sol#485)
	- _updateTopDepositors(owner) (src/TokenBank.sol#205)
		- nextDepositors[prev] = nextDepositors[depositor] (src/TokenBank.sol#436)
		- nextDepositors[depositor] = address(0) (src/TokenBank.sol#437)
		- nextDepositors[depositor] = nextDepositors[candidate] (src/TokenBank.sol#470)
		- nextDepositors[candidate] = depositor (src/TokenBank.sol#471)
		- nextDepositors[cur] = GUARD (src/TokenBank.sol#483)
		- nextDepositors[evicted] = address(0) (src/TokenBank.sol#484)
Reentrancy in TokenBank.depositWithPermit2(address,uint256,uint256,uint256,bytes) (src/TokenBank.sol#229-266):
	External calls:
	- ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature) (src/TokenBank.sol#255-260)
	State variables written after the call(s):
	- balances[owner] += amount (src/TokenBank.sol#262)
	- _updateTopDepositors(owner) (src/TokenBank.sol#263)
		- listSize -- (src/TokenBank.sol#438)
		- listSize ++ (src/TokenBank.sol#472)
		- listSize -- (src/TokenBank.sol#485)
	- _updateTopDepositors(owner) (src/TokenBank.sol#263)
		- nextDepositors[prev] = nextDepositors[depositor] (src/TokenBank.sol#436)
		- nextDepositors[depositor] = address(0) (src/TokenBank.sol#437)
		- nextDepositors[depositor] = nextDepositors[candidate] (src/TokenBank.sol#470)
		- nextDepositors[candidate] = depositor (src/TokenBank.sol#471)
		- nextDepositors[cur] = GUARD (src/TokenBank.sol#483)
		- nextDepositors[evicted] = address(0) (src/TokenBank.sol#484)
Reentrancy in TokenBank.permitDeposit(address,uint256,uint256,uint8,bytes32,bytes32) (src/TokenBank.sol#124-153):
	External calls:
	- IERC20Permit(address(token)).permit(owner,address(this),amount,deadline,v,r,s) (src/TokenBank.sol#135-143)
	State variables written after the call(s):
	- balances[owner] += amount (src/TokenBank.sol#146)
	- _updateTopDepositors(owner) (src/TokenBank.sol#147)
		- listSize -- (src/TokenBank.sol#438)
		- listSize ++ (src/TokenBank.sol#472)
		- listSize -- (src/TokenBank.sol#485)
	- _updateTopDepositors(owner) (src/TokenBank.sol#147)
		- nextDepositors[prev] = nextDepositors[depositor] (src/TokenBank.sol#436)
		- nextDepositors[depositor] = address(0) (src/TokenBank.sol#437)
		- nextDepositors[depositor] = nextDepositors[candidate] (src/TokenBank.sol#470)
		- nextDepositors[candidate] = depositor (src/TokenBank.sol#471)
		- nextDepositors[cur] = GUARD (src/TokenBank.sol#483)
		- nextDepositors[evicted] = address(0) (src/TokenBank.sol#484)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-3
INFO:Detectors:
Detector: reentrancy-events
Reentrancy in AirdopMerkleNFTMarket._executeBuy(uint256) (src/AirdopMerkleNFTMarket.sol#233-249):
	External calls:
	- nftContract.safeTransferFrom(address(this),msg.sender,tokenId) (src/AirdopMerkleNFTMarket.sol#246)
	Event emitted after the call(s):
	- NFTSold(msg.sender,item.seller,tokenId,price) (src/AirdopMerkleNFTMarket.sol#248)
Reentrancy in NFTMarket._executeBuy(uint256,uint256,bool) (src/NFTMarket.sol#229-247):
	External calls:
	- nftContract.safeTransferFrom(address(this),msg.sender,tokenId) (src/NFTMarket.sol#244)
	Event emitted after the call(s):
	- NFTSold(msg.sender,item.seller,tokenId,price) (src/NFTMarket.sol#246)
Reentrancy in NFTMarketV2.buyWithSellerSig(uint256,uint256,uint256,bytes) (src/NFTMarketV2.sol#86-115):
	External calls:
	- nftContract.safeTransferFrom(seller,msg.sender,tokenId) (src/NFTMarketV2.sol#112)
	Event emitted after the call(s):
	- NFTSoldWithSig(msg.sender,seller,tokenId,price,nonce) (src/NFTMarketV2.sol#114)
Reentrancy in AirdopMerkleNFTMarket.cancelListing(uint256) (src/AirdopMerkleNFTMarket.sol#130-140):
	External calls:
	- nftContract.safeTransferFrom(address(this),msg.sender,tokenId) (src/AirdopMerkleNFTMarket.sol#137)
	Event emitted after the call(s):
	- NFTDelisted(msg.sender,tokenId) (src/AirdopMerkleNFTMarket.sol#139)
Reentrancy in NFTMarket.cancelListing(uint256) (src/NFTMarket.sol#294-305):
	External calls:
	- nftContract.safeTransferFrom(address(this),msg.sender,tokenId) (src/NFTMarket.sol#302)
	Event emitted after the call(s):
	- NFTDelisted(msg.sender,tokenId) (src/NFTMarket.sol#304)
Reentrancy in MemeFactory.deployMeme(string,uint256,uint256) (src/MemeFactory.sol#58-89):
	External calls:
	- MemeToken(tokenAddr).initialize(symbol,symbol,totalSupply,perMint,address(this)) (src/MemeFactory.sol#77-83)
	Event emitted after the call(s):
	- MemeDeployed(tokenAddr,symbol,totalSupply,perMint,msg.sender) (src/MemeFactory.sol#88)
Reentrancy in TokenBank.depositWithPermit2(address,ISignatureTransfer.PermitTransferFrom,bytes) (src/TokenBank.sol#173-208):
	External calls:
	- ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature) (src/TokenBank.sol#196-201)
	Event emitted after the call(s):
	- Deposit(owner,permit.permitted.amount) (src/TokenBank.sol#207)
	- TopDepositorEvicted(evicted) (src/TokenBank.sol#486)
		- _updateTopDepositors(owner) (src/TokenBank.sol#205)
	- TopDepositorUpdated(depositor,newBalance) (src/TokenBank.sol#473)
		- _updateTopDepositors(owner) (src/TokenBank.sol#205)
Reentrancy in TokenBank.depositWithPermit2(address,uint256,uint256,uint256,bytes) (src/TokenBank.sol#229-266):
	External calls:
	- ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature) (src/TokenBank.sol#255-260)
	Event emitted after the call(s):
	- Deposit(owner,amount) (src/TokenBank.sol#265)
	- TopDepositorEvicted(evicted) (src/TokenBank.sol#486)
		- _updateTopDepositors(owner) (src/TokenBank.sol#263)
	- TopDepositorUpdated(depositor,newBalance) (src/TokenBank.sol#473)
		- _updateTopDepositors(owner) (src/TokenBank.sol#263)
Reentrancy in MultiSigWallet.execute(uint256) (src/MultiSigWallet.sol#146-165):
	External calls:
	- (success,returnData) = txn.to.call{value: txn.value}(txn.data) (src/MultiSigWallet.sol#161)
	Event emitted after the call(s):
	- TransactionExecuted(_txId,msg.sender) (src/MultiSigWallet.sol#164)
Reentrancy in AirdopMerkleNFTMarket.list(uint256,uint256) (src/AirdopMerkleNFTMarket.sol#110-124):
	External calls:
	- nftContract.safeTransferFrom(msg.sender,address(this),tokenId) (src/AirdopMerkleNFTMarket.sol#121)
	Event emitted after the call(s):
	- NFTListed(msg.sender,tokenId,price) (src/AirdopMerkleNFTMarket.sol#123)
Reentrancy in NFTMarket.list(uint256,uint256) (src/NFTMarket.sol#118-134):
	External calls:
	- nftContract.safeTransferFrom(msg.sender,address(this),tokenId) (src/NFTMarket.sol#131)
	Event emitted after the call(s):
	- NFTListed(msg.sender,tokenId,price) (src/NFTMarket.sol#133)
Reentrancy in MemeFactory.mintMeme(address) (src/MemeFactory.sol#95-107):
	External calls:
	- token.mint(msg.sender,amount) (src/MemeFactory.sol#104)
	Event emitted after the call(s):
	- MemeMinted(tokenAddr,msg.sender,amount) (src/MemeFactory.sol#106)
Reentrancy in TokenBank.permitDeposit(address,uint256,uint256,uint8,bytes32,bytes32) (src/TokenBank.sol#124-153):
	External calls:
	- IERC20Permit(address(token)).permit(owner,address(this),amount,deadline,v,r,s) (src/TokenBank.sol#135-143)
	Event emitted after the call(s):
	- Deposit(owner,amount) (src/TokenBank.sol#152)
	- TopDepositorEvicted(evicted) (src/TokenBank.sol#486)
		- _updateTopDepositors(owner) (src/TokenBank.sol#147)
	- TopDepositorUpdated(depositor,newBalance) (src/TokenBank.sol#473)
		- _updateTopDepositors(owner) (src/TokenBank.sol#147)
Reentrancy in NFTMarket.tokensReceived(address,uint256,bytes) (src/NFTMarket.sol#252-288):
	External calls:
	- nftContract.safeTransferFrom(address(this),from,tokenId) (src/NFTMarket.sol#283)
	Event emitted after the call(s):
	- NFTSold(from,item.seller,tokenId,price) (src/NFTMarket.sol#285)
Reentrancy in Bank.withdraw(uint256) (src/bank.sol#40-48):
	External calls:
	- (success,None) = address(admin).call{value: amount}() (src/bank.sol#44)
	Event emitted after the call(s):
	- Withdrawn(admin,amount) (src/bank.sol#47)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#reentrancy-vulnerabilities-4
INFO:Detectors:
Detector: assembly
AirdopMerkleNFTMarket.permitPrePay(uint256,uint256,bytes) (src/AirdopMerkleNFTMarket.sol#186-201) uses assembly
	- INLINE ASM (src/AirdopMerkleNFTMarket.sol#195-199)
AirdopMerkleNFTMarket.multicall(bytes[]) (src/AirdopMerkleNFTMarket.sol#257-273) uses assembly
	- INLINE ASM (src/AirdopMerkleNFTMarket.sol#263-265)
MyWallet.constructor(string) (src/MyWallet.sol#21-27) uses assembly
	- INLINE ASM (src/MyWallet.sol#23-26)
MyWallet.transferOwernship(address) (src/MyWallet.sol#29-42) uses assembly
	- INLINE ASM (src/MyWallet.sol#32-35)
	- INLINE ASM (src/MyWallet.sol#38-41)
MyWallet.printOwnerSlot() (src/MyWallet.sol#47-54) uses assembly
	- INLINE ASM (src/MyWallet.sol#48-50)
MyWallet.printAllSlots() (src/MyWallet.sol#59-70) uses assembly
	- INLINE ASM (src/MyWallet.sol#60-64)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#assembly-usage
INFO:Detectors:
Detector: dead-code
TokenBank._isPrevDepositor(address,address) (src/TokenBank.sol#507-512) is never used and should be removed
TokenBank._verifyIndex(address,uint256,address) (src/TokenBank.sol#494-502) is never used and should be removed
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#dead-code
INFO:Detectors:
Detector: solc-version
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- StorageWriteRemovalBeforeConditionalTermination
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- InlineAssemblyMemorySideEffects
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
	- ^0.8.13 (src/Counter.sol#2)
	- ^0.8.13 (src/MyERC20.sol#2)
Version constraint ^0.8.0 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation
	- SignedImmutables
	- ABIDecodeTwoDimensionalArrayMemory
	- KeccakCaching.
It is used by:
	- ^0.8.0 (src/ISignatureTransfer.sol#2)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#incorrect-versions-of-solidity
INFO:Detectors:
Detector: low-level-calls
Low level call in AirdopMerkleNFTMarket.multicall(bytes[]) (src/AirdopMerkleNFTMarket.sol#257-273):
	- (success,result) = address(this).delegatecall(data[i]) (src/AirdopMerkleNFTMarket.sol#260)
Low level call in MultiSigWallet.execute(uint256) (src/MultiSigWallet.sol#146-165):
	- (success,returnData) = txn.to.call{value: txn.value}(txn.data) (src/MultiSigWallet.sol#161)
Low level call in Bank.withdraw(uint256) (src/bank.sol#40-48):
	- (success,None) = address(admin).call{value: amount}() (src/bank.sol#44)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#low-level-calls
INFO:Detectors:
Detector: naming-convention
Parameter AirdopMerkleNFTMarket.setAdmin(address)._admin (src/AirdopMerkleNFTMarket.sol#90) is not in mixedCase
Parameter AirdopMerkleNFTMarket.setMerkleRoot(bytes32)._merkleRoot (src/AirdopMerkleNFTMarket.sol#100) is not in mixedCase
Function ISignatureTransfer.DOMAIN_SEPARATOR() (src/ISignatureTransfer.sol#51) is not in mixedCase
Parameter MultiSigWallet.proposal(address,uint256,bytes)._to (src/MultiSigWallet.sol#103) is not in mixedCase
Parameter MultiSigWallet.proposal(address,uint256,bytes)._value (src/MultiSigWallet.sol#104) is not in mixedCase
Parameter MultiSigWallet.proposal(address,uint256,bytes)._data (src/MultiSigWallet.sol#105) is not in mixedCase
Parameter MultiSigWallet.comfirm(uint256)._txId (src/MultiSigWallet.sol#129) is not in mixedCase
Parameter MultiSigWallet.execute(uint256)._txId (src/MultiSigWallet.sol#146) is not in mixedCase
Parameter MultiSigWallet.getTransaction(uint256)._txId (src/MultiSigWallet.sol#177) is not in mixedCase
Parameter MyWallet.transferOwernship(address)._addr (src/MyWallet.sol#29) is not in mixedCase
Function NFTMarket.__NFTMarket_init(address,address,address) (src/NFTMarket.sol#76-83) is not in mixedCase
Parameter NFTMarket.__NFTMarket_init(address,address,address)._paymentToken (src/NFTMarket.sol#76) is not in mixedCase
Parameter NFTMarket.__NFTMarket_init(address,address,address)._nftContract (src/NFTMarket.sol#76) is not in mixedCase
Parameter NFTMarket.__NFTMarket_init(address,address,address)._admin (src/NFTMarket.sol#76) is not in mixedCase
Parameter NFTMarket.initialize(address,address,address)._paymentToken (src/NFTMarket.sol#91) is not in mixedCase
Parameter NFTMarket.initialize(address,address,address)._nftContract (src/NFTMarket.sol#91) is not in mixedCase
Parameter NFTMarket.initialize(address,address,address)._admin (src/NFTMarket.sol#91) is not in mixedCase
Parameter NFTMarket.initialize(address,address)._paymentToken (src/NFTMarket.sol#98) is not in mixedCase
Parameter NFTMarket.initialize(address,address)._nftContract (src/NFTMarket.sol#98) is not in mixedCase
Parameter NFTMarket.setAdmin(address)._admin (src/NFTMarket.sol#106) is not in mixedCase
Function NFTMarket.DOMAIN_SEPARATOR() (src/NFTMarket.sol#319-321) is not in mixedCase
Parameter TokenBank.setPermit2(address)._permit2 (src/TokenBank.sol#74) is not in mixedCase
Function TokenBank._nextDepositors(address) (src/TokenBank.sol#399-403) is not in mixedCase
Function UUNFT.__UUNFT_init(string,string,address) (src/UUNFT.sol#41-46) is not in mixedCase
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#conformance-to-solidity-naming-conventions
INFO:Detectors:
Detector: redundant-statements
Redundant expression "data (src/TokenBank.sol#283)" inTokenBank (src/TokenBank.sol#31-513)
Redundant expression "data (src/TokenBank.sol#305)" inTokenBank (src/TokenBank.sol#31-513)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#redundant-statements
INFO:Detectors:
Detector: too-many-digits
MyERC20.constructor(string,string) (src/MyERC20.sol#7-9) uses literals with too many digits:
	- _mint(msg.sender,1000000 * 10 ** 18) (src/MyERC20.sol#8)
CalledToken.constructor(string,string) (src/CalledToken.sol#24-29) uses literals with too many digits:
	- _mint(msg.sender,1000000 * 10 ** 18) (src/CalledToken.sol#28)
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#too-many-digits
INFO:Detectors:
Detector: cache-array-length
Loop condition i_scope_0 < topDepositors.length (src/bank.sol#62) should use cached array length instead of referencing `length` member of the storage array.
 Loop condition i < topDepositors.length (src/bank.sol#77) should use cached array length instead of referencing `length` member of the storage array.
 Loop condition j < topDepositors.length (src/bank.sol#78) should use cached array length instead of referencing `length` member of the storage array.
 Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#cache-array-length
INFO:Detectors:
Detector: immutable-states
Bank.admin (src/bank.sol#5) should be immutable 
MultiSigWallet.requiredConfirmations (src/MultiSigWallet.sol#24) should be immutable 
Reference: https://github.com/crytic/slither/wiki/Detector-Documentation#state-variables-that-could-be-declared-immutable
INFO:Slither:. analyzed (92 contracts with 101 detectors), 69 result(s) found
**THIS CHECKLIST IS NOT COMPLETE**. Use `--show-ignored-findings` to show all the results.
Summary
 - [uninitialized-state](#uninitialized-state) (1 results) (High)
 - [events-access](#events-access) (1 results) (Low)
 - [missing-zero-check](#missing-zero-check) (1 results) (Low)
 - [calls-loop](#calls-loop) (1 results) (Low)
 - [reentrancy-benign](#reentrancy-benign) (4 results) (Low)
 - [reentrancy-events](#reentrancy-events) (15 results) (Low)
 - [assembly](#assembly) (6 results) (Informational)
 - [dead-code](#dead-code) (2 results) (Informational)
 - [solc-version](#solc-version) (2 results) (Informational)
 - [low-level-calls](#low-level-calls) (3 results) (Informational)
 - [naming-convention](#naming-convention) (24 results) (Informational)
 - [redundant-statements](#redundant-statements) (2 results) (Informational)
 - [too-many-digits](#too-many-digits) (2 results) (Informational)
 - [cache-array-length](#cache-array-length) (3 results) (Optimization)
 - [immutable-states](#immutable-states) (2 results) (Optimization)
## uninitialized-state
Impact: High
Confidence: High
 - [ ] ID-0
[MyWallet.approved](src/MyWallet.sol#L8) is never initialized. It is used in:
	- [MyWallet.printAllSlots()](src/MyWallet.sol#L59-L70)

src/MyWallet.sol#L8


## events-access
Impact: Low
Confidence: Medium
 - [ ] ID-1
[MyWallet.transferOwernship(address)](src/MyWallet.sol#L29-L42) should emit an event for: 
	- [sstore(uint256,uint256)(owner,_addr)](src/MyWallet.sol#L40) 

src/MyWallet.sol#L29-L42


## missing-zero-check
Impact: Low
Confidence: Medium
 - [ ] ID-2
[MemeToken.initialize(string,string,uint256,uint256,address).factory_](src/MemeToken.sol#L43) lacks a zero-check on :
		- [factory = factory_](src/MemeToken.sol#L49)

src/MemeToken.sol#L43


## calls-loop
Impact: Low
Confidence: Medium
 - [ ] ID-3
[AirdopMerkleNFTMarket.multicall(bytes[])](src/AirdopMerkleNFTMarket.sol#L257-L273) has external calls inside a loop: [(success,result) = address(this).delegatecall(data[i])](src/AirdopMerkleNFTMarket.sol#L260)

src/AirdopMerkleNFTMarket.sol#L257-L273


## reentrancy-benign
Impact: Low
Confidence: Medium
 - [ ] ID-4
Reentrancy in [TokenBank.permitDeposit(address,uint256,uint256,uint8,bytes32,bytes32)](src/TokenBank.sol#L124-L153):
	External calls:
	- [IERC20Permit(address(token)).permit(owner,address(this),amount,deadline,v,r,s)](src/TokenBank.sol#L135-L143)
	State variables written after the call(s):
	- [balances[owner] += amount](src/TokenBank.sol#L146)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L147)
		- [listSize --](src/TokenBank.sol#L438)
		- [listSize ++](src/TokenBank.sol#L472)
		- [listSize --](src/TokenBank.sol#L485)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L147)
		- [nextDepositors[prev] = nextDepositors[depositor]](src/TokenBank.sol#L436)
		- [nextDepositors[depositor] = address(0)](src/TokenBank.sol#L437)
		- [nextDepositors[depositor] = nextDepositors[candidate]](src/TokenBank.sol#L470)
		- [nextDepositors[candidate] = depositor](src/TokenBank.sol#L471)
		- [nextDepositors[cur] = GUARD](src/TokenBank.sol#L483)
		- [nextDepositors[evicted] = address(0)](src/TokenBank.sol#L484)

src/TokenBank.sol#L124-L153


 - [ ] ID-5
Reentrancy in [TokenBank.depositWithPermit2(address,uint256,uint256,uint256,bytes)](src/TokenBank.sol#L229-L266):
	External calls:
	- [ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature)](src/TokenBank.sol#L255-L260)
	State variables written after the call(s):
	- [balances[owner] += amount](src/TokenBank.sol#L262)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L263)
		- [listSize --](src/TokenBank.sol#L438)
		- [listSize ++](src/TokenBank.sol#L472)
		- [listSize --](src/TokenBank.sol#L485)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L263)
		- [nextDepositors[prev] = nextDepositors[depositor]](src/TokenBank.sol#L436)
		- [nextDepositors[depositor] = address(0)](src/TokenBank.sol#L437)
		- [nextDepositors[depositor] = nextDepositors[candidate]](src/TokenBank.sol#L470)
		- [nextDepositors[candidate] = depositor](src/TokenBank.sol#L471)
		- [nextDepositors[cur] = GUARD](src/TokenBank.sol#L483)
		- [nextDepositors[evicted] = address(0)](src/TokenBank.sol#L484)

src/TokenBank.sol#L229-L266


 - [ ] ID-6
Reentrancy in [TokenBank.depositWithPermit2(address,ISignatureTransfer.PermitTransferFrom,bytes)](src/TokenBank.sol#L173-L208):
	External calls:
	- [ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature)](src/TokenBank.sol#L196-L201)
	State variables written after the call(s):
	- [balances[owner] += permit.permitted.amount](src/TokenBank.sol#L204)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L205)
		- [listSize --](src/TokenBank.sol#L438)
		- [listSize ++](src/TokenBank.sol#L472)
		- [listSize --](src/TokenBank.sol#L485)
	- [_updateTopDepositors(owner)](src/TokenBank.sol#L205)
		- [nextDepositors[prev] = nextDepositors[depositor]](src/TokenBank.sol#L436)
		- [nextDepositors[depositor] = address(0)](src/TokenBank.sol#L437)
		- [nextDepositors[depositor] = nextDepositors[candidate]](src/TokenBank.sol#L470)
		- [nextDepositors[candidate] = depositor](src/TokenBank.sol#L471)
		- [nextDepositors[cur] = GUARD](src/TokenBank.sol#L483)
		- [nextDepositors[evicted] = address(0)](src/TokenBank.sol#L484)

src/TokenBank.sol#L173-L208


 - [ ] ID-7
Reentrancy in [MemeFactory.deployMeme(string,uint256,uint256)](src/MemeFactory.sol#L58-L89):
	External calls:
	- [MemeToken(tokenAddr).initialize(symbol,symbol,totalSupply,perMint,address(this))](src/MemeFactory.sol#L77-L83)
	State variables written after the call(s):
	- [allMemes.push(tokenAddr)](src/MemeFactory.sol#L86)
	- [isMeme[tokenAddr] = true](src/MemeFactory.sol#L85)

src/MemeFactory.sol#L58-L89


## reentrancy-events
Impact: Low
Confidence: Medium
 - [ ] ID-8
Reentrancy in [NFTMarketV2.buyWithSellerSig(uint256,uint256,uint256,bytes)](src/NFTMarketV2.sol#L86-L115):
	External calls:
	- [nftContract.safeTransferFrom(seller,msg.sender,tokenId)](src/NFTMarketV2.sol#L112)
	Event emitted after the call(s):
	- [NFTSoldWithSig(msg.sender,seller,tokenId,price,nonce)](src/NFTMarketV2.sol#L114)

src/NFTMarketV2.sol#L86-L115


 - [ ] ID-9
Reentrancy in [NFTMarket.tokensReceived(address,uint256,bytes)](src/NFTMarket.sol#L252-L288):
	External calls:
	- [nftContract.safeTransferFrom(address(this),from,tokenId)](src/NFTMarket.sol#L283)
	Event emitted after the call(s):
	- [NFTSold(from,item.seller,tokenId,price)](src/NFTMarket.sol#L285)

src/NFTMarket.sol#L252-L288


 - [ ] ID-10
Reentrancy in [AirdopMerkleNFTMarket.list(uint256,uint256)](src/AirdopMerkleNFTMarket.sol#L110-L124):
	External calls:
	- [nftContract.safeTransferFrom(msg.sender,address(this),tokenId)](src/AirdopMerkleNFTMarket.sol#L121)
	Event emitted after the call(s):
	- [NFTListed(msg.sender,tokenId,price)](src/AirdopMerkleNFTMarket.sol#L123)

src/AirdopMerkleNFTMarket.sol#L110-L124


 - [ ] ID-11
Reentrancy in [TokenBank.depositWithPermit2(address,uint256,uint256,uint256,bytes)](src/TokenBank.sol#L229-L266):
	External calls:
	- [ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature)](src/TokenBank.sol#L255-L260)
	Event emitted after the call(s):
	- [Deposit(owner,amount)](src/TokenBank.sol#L265)
	- [TopDepositorEvicted(evicted)](src/TokenBank.sol#L486)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L263)
	- [TopDepositorUpdated(depositor,newBalance)](src/TokenBank.sol#L473)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L263)

src/TokenBank.sol#L229-L266


 - [ ] ID-12
Reentrancy in [AirdopMerkleNFTMarket._executeBuy(uint256)](src/AirdopMerkleNFTMarket.sol#L233-L249):
	External calls:
	- [nftContract.safeTransferFrom(address(this),msg.sender,tokenId)](src/AirdopMerkleNFTMarket.sol#L246)
	Event emitted after the call(s):
	- [NFTSold(msg.sender,item.seller,tokenId,price)](src/AirdopMerkleNFTMarket.sol#L248)

src/AirdopMerkleNFTMarket.sol#L233-L249


 - [ ] ID-13
Reentrancy in [TokenBank.permitDeposit(address,uint256,uint256,uint8,bytes32,bytes32)](src/TokenBank.sol#L124-L153):
	External calls:
	- [IERC20Permit(address(token)).permit(owner,address(this),amount,deadline,v,r,s)](src/TokenBank.sol#L135-L143)
	Event emitted after the call(s):
	- [Deposit(owner,amount)](src/TokenBank.sol#L152)
	- [TopDepositorEvicted(evicted)](src/TokenBank.sol#L486)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L147)
	- [TopDepositorUpdated(depositor,newBalance)](src/TokenBank.sol#L473)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L147)

src/TokenBank.sol#L124-L153


 - [ ] ID-14
Reentrancy in [MemeFactory.deployMeme(string,uint256,uint256)](src/MemeFactory.sol#L58-L89):
	External calls:
	- [MemeToken(tokenAddr).initialize(symbol,symbol,totalSupply,perMint,address(this))](src/MemeFactory.sol#L77-L83)
	Event emitted after the call(s):
	- [MemeDeployed(tokenAddr,symbol,totalSupply,perMint,msg.sender)](src/MemeFactory.sol#L88)

src/MemeFactory.sol#L58-L89


 - [ ] ID-15
Reentrancy in [MultiSigWallet.execute(uint256)](src/MultiSigWallet.sol#L146-L165):
	External calls:
	- [(success,returnData) = txn.to.call{value: txn.value}(txn.data)](src/MultiSigWallet.sol#L161)
	Event emitted after the call(s):
	- [TransactionExecuted(_txId,msg.sender)](src/MultiSigWallet.sol#L164)

src/MultiSigWallet.sol#L146-L165


 - [ ] ID-16
Reentrancy in [NFTMarket._executeBuy(uint256,uint256,bool)](src/NFTMarket.sol#L229-L247):
	External calls:
	- [nftContract.safeTransferFrom(address(this),msg.sender,tokenId)](src/NFTMarket.sol#L244)
	Event emitted after the call(s):
	- [NFTSold(msg.sender,item.seller,tokenId,price)](src/NFTMarket.sol#L246)

src/NFTMarket.sol#L229-L247


 - [ ] ID-17
Reentrancy in [NFTMarket.cancelListing(uint256)](src/NFTMarket.sol#L294-L305):
	External calls:
	- [nftContract.safeTransferFrom(address(this),msg.sender,tokenId)](src/NFTMarket.sol#L302)
	Event emitted after the call(s):
	- [NFTDelisted(msg.sender,tokenId)](src/NFTMarket.sol#L304)

src/NFTMarket.sol#L294-L305


 - [ ] ID-18
Reentrancy in [AirdopMerkleNFTMarket.cancelListing(uint256)](src/AirdopMerkleNFTMarket.sol#L130-L140):
	External calls:
	- [nftContract.safeTransferFrom(address(this),msg.sender,tokenId)](src/AirdopMerkleNFTMarket.sol#L137)
	Event emitted after the call(s):
	- [NFTDelisted(msg.sender,tokenId)](src/AirdopMerkleNFTMarket.sol#L139)

src/AirdopMerkleNFTMarket.sol#L130-L140


 - [ ] ID-19
Reentrancy in [MemeFactory.mintMeme(address)](src/MemeFactory.sol#L95-L107):
	External calls:
	- [token.mint(msg.sender,amount)](src/MemeFactory.sol#L104)
	Event emitted after the call(s):
	- [MemeMinted(tokenAddr,msg.sender,amount)](src/MemeFactory.sol#L106)

src/MemeFactory.sol#L95-L107


 - [ ] ID-20
Reentrancy in [Bank.withdraw(uint256)](src/bank.sol#L40-L48):
	External calls:
	- [(success,None) = address(admin).call{value: amount}()](src/bank.sol#L44)
	Event emitted after the call(s):
	- [Withdrawn(admin,amount)](src/bank.sol#L47)

src/bank.sol#L40-L48


 - [ ] ID-21
Reentrancy in [NFTMarket.list(uint256,uint256)](src/NFTMarket.sol#L118-L134):
	External calls:
	- [nftContract.safeTransferFrom(msg.sender,address(this),tokenId)](src/NFTMarket.sol#L131)
	Event emitted after the call(s):
	- [NFTListed(msg.sender,tokenId,price)](src/NFTMarket.sol#L133)

src/NFTMarket.sol#L118-L134


 - [ ] ID-22
Reentrancy in [TokenBank.depositWithPermit2(address,ISignatureTransfer.PermitTransferFrom,bytes)](src/TokenBank.sol#L173-L208):
	External calls:
	- [ISignatureTransfer(permit2).permitTransferFrom(permit,transferDetails,owner,signature)](src/TokenBank.sol#L196-L201)
	Event emitted after the call(s):
	- [Deposit(owner,permit.permitted.amount)](src/TokenBank.sol#L207)
	- [TopDepositorEvicted(evicted)](src/TokenBank.sol#L486)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L205)
	- [TopDepositorUpdated(depositor,newBalance)](src/TokenBank.sol#L473)
		- [_updateTopDepositors(owner)](src/TokenBank.sol#L205)

src/TokenBank.sol#L173-L208


## assembly
Impact: Informational
Confidence: High
 - [ ] ID-23
[AirdopMerkleNFTMarket.multicall(bytes[])](src/AirdopMerkleNFTMarket.sol#L257-L273) uses assembly
	- [INLINE ASM](src/AirdopMerkleNFTMarket.sol#L263-L265)

src/AirdopMerkleNFTMarket.sol#L257-L273


 - [ ] ID-24
[MyWallet.constructor(string)](src/MyWallet.sol#L21-L27) uses assembly
	- [INLINE ASM](src/MyWallet.sol#L23-L26)

src/MyWallet.sol#L21-L27


 - [ ] ID-25
[MyWallet.printAllSlots()](src/MyWallet.sol#L59-L70) uses assembly
	- [INLINE ASM](src/MyWallet.sol#L60-L64)

src/MyWallet.sol#L59-L70


 - [ ] ID-26
[MyWallet.printOwnerSlot()](src/MyWallet.sol#L47-L54) uses assembly
	- [INLINE ASM](src/MyWallet.sol#L48-L50)

src/MyWallet.sol#L47-L54


 - [ ] ID-27
[AirdopMerkleNFTMarket.permitPrePay(uint256,uint256,bytes)](src/AirdopMerkleNFTMarket.sol#L186-L201) uses assembly
	- [INLINE ASM](src/AirdopMerkleNFTMarket.sol#L195-L199)

src/AirdopMerkleNFTMarket.sol#L186-L201


 - [ ] ID-28
[MyWallet.transferOwernship(address)](src/MyWallet.sol#L29-L42) uses assembly
	- [INLINE ASM](src/MyWallet.sol#L32-L35)
	- [INLINE ASM](src/MyWallet.sol#L38-L41)

src/MyWallet.sol#L29-L42


## dead-code
Impact: Informational
Confidence: Medium
 - [ ] ID-29
[TokenBank._isPrevDepositor(address,address)](src/TokenBank.sol#L507-L512) is never used and should be removed

src/TokenBank.sol#L507-L512


 - [ ] ID-30
[TokenBank._verifyIndex(address,uint256,address)](src/TokenBank.sol#L494-L502) is never used and should be removed

src/TokenBank.sol#L494-L502


## solc-version
Impact: Informational
Confidence: High
 - [ ] ID-31
Version constraint ^0.8.0 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation
	- SignedImmutables
	- ABIDecodeTwoDimensionalArrayMemory
	- KeccakCaching.
It is used by:
	- [^0.8.0](src/ISignatureTransfer.sol#L2)

src/ISignatureTransfer.sol#L2


 - [ ] ID-32
Version constraint ^0.8.13 contains known severe issues (https://solidity.readthedocs.io/en/latest/bugs.html)
	- VerbatimInvalidDeduplication
	- FullInlinerNonExpressionSplitArgumentEvaluationOrder
	- MissingSideEffectsOnSelectorAccess
	- StorageWriteRemovalBeforeConditionalTermination
	- AbiReencodingHeadOverflowWithStaticArrayCleanup
	- DirtyBytesArrayToStorage
	- InlineAssemblyMemorySideEffects
	- DataLocationChangeInInternalOverride
	- NestedCalldataArrayAbiReencodingSizeValidation.
It is used by:
	- [^0.8.13](src/Counter.sol#L2)
	- [^0.8.13](src/MyERC20.sol#L2)

src/Counter.sol#L2


## low-level-calls
Impact: Informational
Confidence: High
 - [ ] ID-33
Low level call in [AirdopMerkleNFTMarket.multicall(bytes[])](src/AirdopMerkleNFTMarket.sol#L257-L273):
	- [(success,result) = address(this).delegatecall(data[i])](src/AirdopMerkleNFTMarket.sol#L260)

src/AirdopMerkleNFTMarket.sol#L257-L273


 - [ ] ID-34
Low level call in [Bank.withdraw(uint256)](src/bank.sol#L40-L48):
	- [(success,None) = address(admin).call{value: amount}()](src/bank.sol#L44)

src/bank.sol#L40-L48


 - [ ] ID-35
Low level call in [MultiSigWallet.execute(uint256)](src/MultiSigWallet.sol#L146-L165):
	- [(success,returnData) = txn.to.call{value: txn.value}(txn.data)](src/MultiSigWallet.sol#L161)

src/MultiSigWallet.sol#L146-L165


## naming-convention
Impact: Informational
Confidence: High
 - [ ] ID-36
Parameter [MultiSigWallet.proposal(address,uint256,bytes)._data](src/MultiSigWallet.sol#L105) is not in mixedCase

src/MultiSigWallet.sol#L105


 - [ ] ID-37
Parameter [MultiSigWallet.proposal(address,uint256,bytes)._value](src/MultiSigWallet.sol#L104) is not in mixedCase

src/MultiSigWallet.sol#L104


 - [ ] ID-38
Parameter [AirdopMerkleNFTMarket.setAdmin(address)._admin](src/AirdopMerkleNFTMarket.sol#L90) is not in mixedCase

src/AirdopMerkleNFTMarket.sol#L90


 - [ ] ID-39
Parameter [MultiSigWallet.proposal(address,uint256,bytes)._to](src/MultiSigWallet.sol#L103) is not in mixedCase

src/MultiSigWallet.sol#L103


 - [ ] ID-40
Parameter [NFTMarket.initialize(address,address)._nftContract](src/NFTMarket.sol#L98) is not in mixedCase

src/NFTMarket.sol#L98


 - [ ] ID-41
Parameter [NFTMarket.initialize(address,address,address)._admin](src/NFTMarket.sol#L91) is not in mixedCase

src/NFTMarket.sol#L91


 - [ ] ID-42
Function [ISignatureTransfer.DOMAIN_SEPARATOR()](src/ISignatureTransfer.sol#L51) is not in mixedCase

src/ISignatureTransfer.sol#L51


 - [ ] ID-43
Parameter [NFTMarket.__NFTMarket_init(address,address,address)._admin](src/NFTMarket.sol#L76) is not in mixedCase

src/NFTMarket.sol#L76


 - [ ] ID-44
Function [NFTMarket.DOMAIN_SEPARATOR()](src/NFTMarket.sol#L319-L321) is not in mixedCase

src/NFTMarket.sol#L319-L321


 - [ ] ID-45
Function [UUNFT.__UUNFT_init(string,string,address)](src/UUNFT.sol#L41-L46) is not in mixedCase

src/UUNFT.sol#L41-L46


 - [ ] ID-46
Parameter [NFTMarket.__NFTMarket_init(address,address,address)._paymentToken](src/NFTMarket.sol#L76) is not in mixedCase

src/NFTMarket.sol#L76


 - [ ] ID-47
Parameter [NFTMarket.__NFTMarket_init(address,address,address)._nftContract](src/NFTMarket.sol#L76) is not in mixedCase

src/NFTMarket.sol#L76


 - [ ] ID-48
Parameter [MultiSigWallet.execute(uint256)._txId](src/MultiSigWallet.sol#L146) is not in mixedCase

src/MultiSigWallet.sol#L146


 - [ ] ID-49
Function [NFTMarket.__NFTMarket_init(address,address,address)](src/NFTMarket.sol#L76-L83) is not in mixedCase

src/NFTMarket.sol#L76-L83


 - [ ] ID-50
Parameter [NFTMarket.initialize(address,address)._paymentToken](src/NFTMarket.sol#L98) is not in mixedCase

src/NFTMarket.sol#L98


 - [ ] ID-51
Parameter [NFTMarket.initialize(address,address,address)._paymentToken](src/NFTMarket.sol#L91) is not in mixedCase

src/NFTMarket.sol#L91


 - [ ] ID-52
Parameter [AirdopMerkleNFTMarket.setMerkleRoot(bytes32)._merkleRoot](src/AirdopMerkleNFTMarket.sol#L100) is not in mixedCase

src/AirdopMerkleNFTMarket.sol#L100


 - [ ] ID-53
Parameter [MultiSigWallet.comfirm(uint256)._txId](src/MultiSigWallet.sol#L129) is not in mixedCase

src/MultiSigWallet.sol#L129


 - [ ] ID-54
Parameter [NFTMarket.setAdmin(address)._admin](src/NFTMarket.sol#L106) is not in mixedCase

src/NFTMarket.sol#L106


 - [ ] ID-55
Parameter [TokenBank.setPermit2(address)._permit2](src/TokenBank.sol#L74) is not in mixedCase

src/TokenBank.sol#L74


 - [ ] ID-56
Parameter [MyWallet.transferOwernship(address)._addr](src/MyWallet.sol#L29) is not in mixedCase

src/MyWallet.sol#L29


 - [ ] ID-57
Parameter [NFTMarket.initialize(address,address,address)._nftContract](src/NFTMarket.sol#L91) is not in mixedCase

src/NFTMarket.sol#L91


 - [ ] ID-58
Function [TokenBank._nextDepositors(address)](src/TokenBank.sol#L399-L403) is not in mixedCase

src/TokenBank.sol#L399-L403


 - [ ] ID-59
Parameter [MultiSigWallet.getTransaction(uint256)._txId](src/MultiSigWallet.sol#L177) is not in mixedCase

src/MultiSigWallet.sol#L177


## redundant-statements
Impact: Informational
Confidence: High
 - [ ] ID-60
Redundant expression "[data](src/TokenBank.sol#L283)" in[TokenBank](src/TokenBank.sol#L31-L513)

src/TokenBank.sol#L283


 - [ ] ID-61
Redundant expression "[data](src/TokenBank.sol#L305)" in[TokenBank](src/TokenBank.sol#L31-L513)

src/TokenBank.sol#L305


## too-many-digits
Impact: Informational
Confidence: Medium
 - [ ] ID-62
[CalledToken.constructor(string,string)](src/CalledToken.sol#L24-L29) uses literals with too many digits:
	- [_mint(msg.sender,1000000 * 10 ** 18)](src/CalledToken.sol#L28)

src/CalledToken.sol#L24-L29


 - [ ] ID-63
[MyERC20.constructor(string,string)](src/MyERC20.sol#L7-L9) uses literals with too many digits:
	- [_mint(msg.sender,1000000 * 10 ** 18)](src/MyERC20.sol#L8)

src/MyERC20.sol#L7-L9


## cache-array-length
Impact: Optimization
Confidence: High
 - [ ] ID-64
Loop condition [i_scope_0 < topDepositors.length](src/bank.sol#L62) should use cached array length instead of referencing `length` member of the storage array.
 
src/bank.sol#L62


 - [ ] ID-65
Loop condition [j < topDepositors.length](src/bank.sol#L78) should use cached array length instead of referencing `length` member of the storage array.
 
src/bank.sol#L78


 - [ ] ID-66
Loop condition [i < topDepositors.length](src/bank.sol#L77) should use cached array length instead of referencing `length` member of the storage array.
 
src/bank.sol#L77


## immutable-states
Impact: Optimization
Confidence: High
 - [ ] ID-67
[Bank.admin](src/bank.sol#L5) should be immutable 

src/bank.sol#L5


 - [ ] ID-68
[MultiSigWallet.requiredConfirmations](src/MultiSigWallet.sol#L24) should be immutable 

src/MultiSigWallet.sol#L24


