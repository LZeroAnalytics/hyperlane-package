const ethers = require('ethers')
;(async () => {
  const ORIGIN_RPC = 'https://ethereum-sepolia-rpc.publicnode.com'
  const KEY = '0x0820e79cde729336c29c6d3f5102b522f625b4b1e5801f097848600a23e15cb2'
  const MAILBOX = '0x34b1de7C7497e4e83EfC07862bC853B19b60649C'
  const DEST = 421614 // arbitrum sepolia
  const RECIP = '0x23526f2E2ECDC16038d9C5d8BCc0ac5Bc2e76f6a'

  const provider = new ethers.providers.JsonRpcProvider(ORIGIN_RPC)
  const wallet = new ethers.Wallet(KEY, provider)
  const abi = ['function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes message)']
  const mailbox = new ethers.Contract(MAILBOX, abi, wallet)
  const recipient32 = ethers.utils.hexZeroPad(RECIP, 32)
  const message = '0x'

  console.log('Dispatching...')
  const tx = await mailbox.dispatch(DEST, recipient32, message)
  console.log('dispatch tx:', tx.hash)
  const rcpt = await tx.wait()
  console.log('confirmed in block', rcpt.blockNumber)
})().catch((e) => { console.error(e); process.exit(1) })
