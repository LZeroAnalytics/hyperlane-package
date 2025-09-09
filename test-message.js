#!/usr/bin/env node

const { ethers } = require('ethers');

async function sendTestMessage() {
    // Configuration
    const SEPOLIA_RPC = 'https://eth-sepolia.g.alchemy.com/v2/lC2HDPB2Vs7-p-UPkgKD-VqFulU5elyk';
    const SEPOLIA_MAILBOX = '0x2cBa90A2bc9FAB54B4d34DFEB55f8224E6Af1635';
    const BASE_SEPOLIA_DOMAIN = 84532;
    const BASE_TEST_RECIPIENT = '0xb10045bfF916eCe811dc66Ca6C0311fD45c48dd4';
    const DEPLOYER_KEY = '0x89c964f3b1987e037e093b2fa4e5f1e9b6ed2e08c8d0f088c59f92f756c09e09';
    
    // Connect to Sepolia
    const provider = new ethers.providers.JsonRpcProvider(SEPOLIA_RPC);
    const wallet = new ethers.Wallet(DEPLOYER_KEY, provider);
    
    console.log('Wallet address:', wallet.address);
    const balance = await wallet.getBalance();
    console.log('Balance:', ethers.utils.formatEther(balance), 'ETH');
    
    // Mailbox ABI (only dispatch function)
    const mailboxABI = [
        "function dispatch(uint32 _destinationDomain, bytes32 _recipientAddress, bytes calldata _messageBody) external payable returns (bytes32)"
    ];
    
    // Create contract instance
    const mailbox = new ethers.Contract(SEPOLIA_MAILBOX, mailboxABI, wallet);
    
    // Prepare message
    const recipientBytes32 = ethers.utils.hexZeroPad(BASE_TEST_RECIPIENT, 32);
    const messageBody = ethers.utils.toUtf8Bytes("Hello from Sepolia to Base Sepolia!");
    
    console.log('Sending message to Base Sepolia...');
    console.log('Destination domain:', BASE_SEPOLIA_DOMAIN);
    console.log('Recipient:', BASE_TEST_RECIPIENT);
    
    try {
        // Send the message
        const tx = await mailbox.dispatch(
            BASE_SEPOLIA_DOMAIN,
            recipientBytes32,
            messageBody,
            { 
                value: ethers.utils.parseEther("0.001"), // Include some ETH for gas payment
                gasLimit: 300000
            }
        );
        
        console.log('Transaction hash:', tx.hash);
        console.log('Waiting for confirmation...');
        
        const receipt = await tx.wait();
        console.log('Message sent successfully!');
        console.log('Block number:', receipt.blockNumber);
        console.log('Gas used:', receipt.gasUsed.toString());
        
        // Look for Dispatch event
        const dispatchEvent = receipt.logs.find(log => {
            try {
                const parsed = mailbox.interface.parseLog(log);
                return parsed.name === 'Dispatch';
            } catch {
                return false;
            }
        });
        
        if (dispatchEvent) {
            console.log('Message ID:', dispatchEvent.topics[1]);
        }
        
    } catch (error) {
        console.error('Error sending message:', error.message);
    }
}

sendTestMessage().catch(console.error);