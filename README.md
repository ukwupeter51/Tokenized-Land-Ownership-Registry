# 🏡 Tokenized Land Ownership Registry

A blockchain-based land registry system that represents land deeds as NFTs on the Stacks blockchain. This smart contract enables secure, transparent, and verifiable land ownership transfers with on-chain enforcement.

## 🌟 Features

- 🏠 **NFT Land Deeds**: Each land parcel is represented as a unique NFT
- 📍 **Detailed Land Records**: Store coordinates, size, type, and market value
- ✅ **Verification System**: Authorized surveyors can register and verify land
- 💰 **Secure Transfers**: Built-in escrow system for safe ownership transfers
- 📊 **Transfer History**: Complete on-chain record of all ownership changes
- 🔐 **Access Control**: Role-based permissions for surveyors and contract owner

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation

1. Clone the repository
2. Navigate to the project directory
3. Run Clarinet commands to interact with the contract

## 📋 Contract Functions

### 🏗️ Land Registration

**`register-land`** - Register a new land parcel (surveyors only)
```clarity
(contract-call? .land-registry register-land "40.7128,-74.0060" u1000 "residential" u500000)
```

**`verify-land`** - Verify registered land (contract owner only)
```clarity
(contract-call? .land-registry verify-land u1)
```

### 🔄 Ownership Transfers

**`initiate-transfer`** - Start a land transfer process
```clarity
(contract-call? .land-registry initiate-transfer u1 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u500000)
```

**`complete-transfer`** - Complete the transfer with payment
```clarity
(contract-call? .land-registry complete-transfer u1)
```

**`cancel-transfer`** - Cancel a pending transfer
```clarity
(contract-call? .land-registry cancel-transfer u1)
```

### 📊 Query Functions

**`get-land-details`** - Get detailed information about a land parcel
```clarity
(contract-call? .land-registry get-land-details u1)
```

**`get-owner`** - Get the current owner of a land NFT
```clarity
(contract-call? .land-registry get-owner u1)
```

**`get-transfer-history`** - View transfer history for a land parcel
```clarity
(contract-call? .land-registry get-transfer-history u1)
```

**`is-land-verified`** - Check if land is verified
```clarity
(contract-call? .land-registry is-land-verified u1)
```

**`has-pending-transfer`** - Check if land has pending transfer
```clarity
(contract-call? .land-registry has-pending-transfer u1)
```

### 👥 Administration

**`authorize-surveyor`** - Authorize a new surveyor (owner only)
````clarity
(contract-call? .land-registry authorize-surveyor 'SP2J6ZY48GV1EZ5V2V
