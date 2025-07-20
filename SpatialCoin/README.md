# GeoCrypt AR Treasure Protocol

> A location-based AR treasure hunting platform with crypto rewards built on Stacks blockchain

## Overview

The GeoCrypt AR Treasure Protocol enables users to create and discover virtual treasure anchors tied to real-world GPS coordinates. By combining augmented reality with blockchain technology, the protocol creates a gamified exploration experience where physical movement generates digital rewards.

## Core Concept

**Spatial NFT Anchoring** - Digital treasures are cryptographically locked to specific geographic coordinates, creating location-based value that can only be claimed through physical presence.

## Smart Contract: `geo-anchor-rewards.clar`

### Key Features

🎯 **AR Treasure Anchoring**
- Create virtual treasures anchored to real-world GPS coordinates
- Rarity tier system with bonus multipliers (Common, Rare, Epic, Legendary)
- Staking mechanism to prevent spam and ensure quality

📍 **GPS-Verified Discovery**
- Proximity validation using coordinate hashing
- Anti-cheat mechanisms with cooldown periods
- Cryptographic location proofs

🎮 **Treasure Hunt Campaigns**
- Multi-anchor treasure hunt experiences
- Configurable duration and bonus systems
- Progress tracking and completion rewards

💰 **Economic Incentives**
- Creator commission system (10% of rewards)
- Platform sustainability fees (5%)
- Reputation-based scoring system

## Contract Functions

### Public Functions

| Function | Description | Access |
|----------|-------------|---------|
| `register-hunter` | Register as a treasure hunter | Anyone |
| `create-anchor` | Create a new AR treasure anchor | Registered Users |
| `claim-treasure-reward` | Claim reward by proving proximity | Hunters |
| `create-treasure-campaign` | Create multi-anchor campaigns | Anyone |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-anchor` | Retrieve anchor details | Anchor data |
| `get-hunter-profile` | Get hunter statistics | Hunter profile |
| `get-campaign` | Campaign information | Campaign data |
| `has-claimed-anchor` | Check if anchor already claimed | Boolean |
| `get-area-density` | Get anchor density for area | Density stats |
| `get-platform-stats` | Global platform metrics | Platform data |

## Data Structures

### Anchors
```clarity
{
  creator: principal,
  latitude: int,           // GPS coordinates in micro-degrees
  longitude: int,
  reward-pool: uint,       // SPATIAL tokens for discovery
  metadata-uri: string,    // AR object metadata (IPFS)
  rarity-tier: uint,       // 1=Common, 2=Rare, 3=Epic, 4=Legendary
  created-at: uint,        // Block height
  total-claims: uint,      // Number of discoveries
  is-active: bool,         // Active status
  stake-amount: uint       // Creator's stake
}
```

### Treasure Hunters
```clarity
{
  total-discoveries: uint,
  total-rewards: uint,
  last-claim-block: uint,
  reputation-score: uint,
  is-verified: bool
}
```

### Anchor Claims
```clarity
{
  claimed-at: uint,
  reward-amount: uint,
  gps-proof-hash: buff     // Cryptographic location proof
}
```

## Economic Model

### Rarity Tiers & Bonuses
- **Common (Tier 1)**: 100% base reward
- **Rare (Tier 2)**: 150% base reward  
- **Epic (Tier 3)**: 250% base reward
- **Legendary (Tier 4)**: 500% base reward

### Fee Structure
- **Creator Commission**: 10% of each discovery reward
- **Platform Fee**: 5% for ecosystem sustainability
- **Net Hunter Reward**: 85% of calculated reward

### Anti-Spam Mechanisms
- **Minimum Stake**: 1,000 SPATIAL tokens per anchor
- **Area Density Limit**: Maximum 10 anchors per 1km² area
- **Cooldown Period**: 24 hours between claims (~144 blocks)
- **Proximity Threshold**: 50 meters validation radius

## Usage Examples

### Creating an Anchor
```clarity
(contract-call? .geo-anchor-rewards create-anchor
  23500000        ;; latitude (23.5°N in micro-degrees)
  90250000        ;; longitude (90.25°E in micro-degrees)
  u500            ;; 500 SPATIAL token reward
  "ipfs://..."    ;; AR object metadata URI
  u2              ;; Rare tier
  u1000           ;; 1000 SPATIAL stake
)
```

### Claiming a Treasure
```clarity
(contract-call? .geo-anchor-rewards claim-treasure-reward
  u1              ;; anchor-id
  23500050        ;; proof latitude
  90250030        ;; proof longitude
  0x1234...       ;; GPS proof hash
)
```

### Creating a Campaign
```clarity
(contract-call? .geo-anchor-rewards create-treasure-campaign
  "Detroit Revival Quest"
  (list u1 u2 u3 u4 u5)  ;; anchor IDs
  u5000                   ;; total campaign rewards
  u1440                   ;; duration (10 days)
  u3                      ;; minimum discoveries
  u200                    ;; 2x bonus multiplier
)
```

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | `ERR-NOT-AUTHORIZED` | User not registered or insufficient permissions |
| 101 | `ERR-ANCHOR-NOT-FOUND` | Anchor ID does not exist |
| 102 | `ERR-INVALID-COORDINATES` | GPS coordinates out of valid range |
| 103 | `ERR-INSUFFICIENT-STAKE` | Stake amount below minimum requirement |
| 104 | `ERR-ALREADY-CLAIMED` | Treasure already claimed by this hunter |
| 105 | `ERR-TOO-FAR-FROM-ANCHOR` | GPS proof outside proximity threshold |
| 106 | `ERR-COOLDOWN-ACTIVE` | Must wait before next claim |
| 107 | `ERR-CAMPAIGN-NOT-FOUND` | Campaign ID does not exist |
| 108 | `ERR-CAMPAIGN-ENDED` | Campaign has expired |
| 109 | `ERR-INVALID-PROOF` | GPS proof validation failed |
| 110 | `ERR-ANCHOR-DENSITY-EXCEEDED` | Too many anchors in area |

## Security Features

### GPS Validation
- **Coordinate Bounds**: Earth's valid latitude (-90° to 90°) and longitude (-180° to 180°) ranges
- **Proximity Verification**: Haversine distance calculation for location validation
- **Proof Hashing**: Cryptographic GPS proofs prevent location spoofing

### Economic Security
- **Stake Slashing**: Future implementation for fraudulent anchors
- **Reputation System**: Score-based trust mechanism
- **Area Limits**: Prevent anchor spam in popular locations

### Smart Contract Security
- **Input Validation**: All user inputs sanitized and bounds-checked
- **Access Controls**: Function-level permission management
- **Overflow Protection**: Safe arithmetic operations throughout

## Integration Points

### Dependencies
- **SpatialCoin Token** (`spatial-coin-token.clar`) - For staking and rewards
- **AR NFT Collection** (`ar-nft-collection.clar`) - For treasure metadata
- **Proximity Validator** (`proximity-validator.clar`) - Advanced GPS validation

### External Integrations
- **IPFS**: Metadata storage for AR objects
- **Mobile AR Apps**: Real-world treasure discovery interface
- **Oracle Services**: Enhanced GPS validation (future)

## Deployment Requirements

### Prerequisites
- Stacks blockchain testnet/mainnet access
- SpatialCoin token contract deployed
- IPFS infrastructure for metadata storage

### Configuration
```toml
# Clarinet.toml
[contracts.geo-anchor-rewards]
path = "contracts/geo-anchor-rewards.clar"
dependencies = ["spatial-coin-token"]
```

## Use Cases

### Tourism & Local Economy
- **City Exploration**: Gamified tourist experiences with local business integration
- **Economic Development**: Drive foot traffic to underutilized neighborhoods
- **Cultural Heritage**: Interactive historical site discovery

### Corporate Applications  
- **Team Building**: Corporate treasure hunts and team activities
- **Marketing Campaigns**: Location-based brand engagement
- **Real Estate**: Property discovery and area highlighting

### Educational Applications
- **Campus Tours**: University orientation and campus exploration
- **Field Studies**: Location-based learning experiences
- **Research Data**: Crowdsourced geographic data collection

## Future Enhancements

- **IoT Integration**: Automated anchor creation from sensor networks
- **Cross-Chain Bridges**: Multi-blockchain treasure discovery
- **Machine Learning**: Dynamic reward optimization
- **Advanced Anti-Cheat**: Behavioral analysis and fraud detection

## Contributing

The GeoCrypt AR Treasure Protocol is designed for community contribution and ecosystem growth. Developers can extend the protocol through:

- Enhanced GPS validation algorithms
- AR object rendering improvements  
- Economic model optimizations
- Anti-cheat mechanism enhancements

---

**Built for the future of location-based digital experiences** 🌍✨