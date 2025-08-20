const ethers = require('ethers')
;(async () => {
  const ORIGIN_RPC = 'https://eth-sepolia.g.alchemy.com/v2/lC2HDPB2Vs7-p-UPkgKD-VqFulU5elyk'
  const DEST_RPC = 'https://arb-sepolia.g.alchemy.com/v2/lC2HDPB2Vs7-p-UPkgKD-VqFulU5elyk'
  const KEY = '0x0820e79cde729336c29c6d3f5102b522f625b4b1e5801f097848600a23e15cb2'
  const MAILBOX_ORIGIN = '0x6BBC3b2295445b77d6d56899c1EAed19520d8485'
  const MAILBOX_DEST = '0x393604d926BaD5008Dc8a138eA7329e220bF0A1b'
  const RECIP = '0x95927E330e7b2a11D782D075F67bF86284951aE6' // testRecipient on dest
  const providerO = new ethers.providers.JsonRpcProvider(ORIGIN_RPC)
  const providerD = new ethers.providers.JsonRpcProvider(DEST_RPC)
  const wallet = new ethers.Wallet(KEY, providerO)
  const abi = [
    'function quoteDispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes message) view returns (uint256 fee)',
    'function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes message) payable returns (bytes32 messageId)',
    'function latestDispatchedId() view returns (bytes32)',
    'function delivered(bytes32) view returns (bool)',
    'function defaultHook() view returns (address)'
  ]
  const mO = new ethers.Contract(MAILBOX_ORIGIN, abi, wallet)
  const mD = new ethers.Contract(MAILBOX_DEST, abi, providerD)
  const DEST = 421614
  const recipient32 = ethers.utils.hexZeroPad(RECIP, 32)
  const msg = '0x'
  try {
    const hook = await mO.defaultHook()
    console.log('defaultHook on origin:', hook)
  } catch {}
  let fee = ethers.BigNumber.from(0)
  try {
    fee = await mO.quoteDispatch(DEST, recipient32, msg)
  } catch (e) {
    console.log('quoteDispatch failed, proceeding with zero fee:', e.message || e)
  }
  console.log('fee (wei):', fee.toString())
  const tx = await mO.dispatch(DEST, recipient32, msg, { value: fee })
  console.log('dispatch tx:', tx.hash)
  const rcpt = await tx.wait()
  console.log('confirmed in block', rcpt.blockNumber)
  const msgId = await mO.latestDispatchedId()
  console.log('messageId:', msgId)
  // quick poll delivered on dest
  for (let i = 0; i < 60; i++) {
    const del = await mD.delivered(msgId)
    console.log(`[delivered?] ${del} (attempt ${i})`)
    if (del) break
    await new Promise(r => setTimeout(r, 5000))
  }
})().catch(e => { console.error(e); process.exit(1) })
