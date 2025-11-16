# Z/IP Gateway Architecture

## Overview

The Z/IP Gateway is a sophisticated software bridge that enables IP-based applications to communicate with Z-Wave devices. It acts as a transparent gateway, translating between IP protocols (IPv4/IPv6) and Z-Wave protocols, while providing comprehensive security, network management, and service discovery features.

**Version**: 7.18.05
**Status**: Maintenance Mode (Critical fixes only)
**Migration Path**: For new projects, migrate to [z-wave-protocol-controller](https://github.com/SiliconLabsSoftware/z-wave-protocol-controller)

## High-Level Architecture

The Z/IP Gateway follows a three-tier layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                      LAN Side (IP)                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ ZIP Clients │  │   mDNS      │  │   DTLS      │         │
│  │  (IPv4/v6)  │  │  Discovery  │  │  Security   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    Tier 1: Gateway Core                     │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  ZIP_Router (Event Dispatcher & Main Loop)          │   │
│  └─────────────────────────────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ Network Mgmt FSM │  │  Resource Directory          │   │
│  │  (30+ states)    │  │  (Node Database & Probing)   │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │  Bridge (IP      │  │  Mailbox (Command Queueing)  │   │
│  │  Emulation)      │  │  (2000 entry capacity)       │   │
│  └──────────────────┘  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Tier 2: Security & Transport                   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │  S2 Protocol     │  │  S2 Inclusion FSM            │   │
│  │  (52 KB)         │  │  (ECDH Key Exchange)         │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ Transport Svc 2  │  │  Security Layer              │   │
│  │  (9-state FSM)   │  │  (S0/S2 Routing)             │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  Serial API (NCP Communication - 119 KB)             │ │
│  └──────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  Tier 3: Networking                         │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │  mDNS Service    │  │  IPv4/IPv6 Support           │   │
│  │  (70 KB)         │  │  (with NAT)                  │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ Multicast Groups │  │  DHCP Server                 │   │
│  └──────────────────┘  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                  PAN Side (Z-Wave)                          │
│  Serial API → Z-Wave Controller (NCP) → Z-Wave Network     │
└─────────────────────────────────────────────────────────────┘
```

See [architecture_overview.puml](architecture_overview.puml) for detailed component diagram.

## Core Components

### Tier 1: Gateway Core

#### ZIP_Router (src/ZIP_Router.c - 1,813 lines)
The central event dispatcher and main control loop of the gateway.

**Responsibilities:**
- Event dispatching and processing
- Main event loop coordination
- Component lifecycle management
- Integration of all subsystems

#### Network Management FSM (src/CC_NetworkManagement.c - 3,420 lines)
Complex finite state machine handling all network management operations.

**States**: 30+ states including:
- Node addition (classic, S2, Smart Start)
- Node removal and replacement
- Learn mode (inclusion/exclusion)
- Proxy inclusion
- Network healing

**Key Operations:**
- Node inclusion with multiple security levels
- Smart Start touch-free inclusion
- Proxy inclusion for multi-controller networks
- Node interview and probing
- Secure bootstrapping coordination

See [network_management_fsm.puml](network_management_fsm.puml) for state diagram.

#### Resource Directory (src/ResourceDirectory.c - 2,930 lines)
Maintains a comprehensive database of all nodes in the Z-Wave network.

**Features:**
- Node capability caching
- Multi-endpoint support
- Probing state machine for node interview
- Command class version tracking
- Node security information

**Probing Process:**
1. Node Info Frame collection
2. Command Class version queries
3. Endpoint discovery (Multi-Channel)
4. Security capability detection

#### Bridge Module (src/Bridge.c)
Provides IP emulation for Z-Wave devices.

**Functions:**
- Virtual node management for IP associations
- ICMP Echo (ping) emulation via Z-Wave NOP
- IPv4/IPv6 address assignment
- Association proxy for cross-PAN associations

#### Mailbox Service (src/Mailbox.c)
Queue management for non-listening (battery-powered) nodes.

**Specifications:**
- Queue capacity: 2000 entries
- Automatic wake-up handling
- Queue persistence across restarts
- "NAK Waiting" notifications every 60s
- UDP ACK request every 10 minutes

### Tier 2: Security & Transport

#### S2 Protocol (libs2/protocol/S2.c - 52 KB)
Implementation of the Z-Wave Security 2 command class.

**Security Classes:**
- **S2_UNAUTHENTICATED**: Basic encryption (Key Slot 0)
- **S2_AUTHENTICATED**: Authenticated encryption (Key Slot 1)
- **S2_ACCESS**: Highest security level (Key Slot 2)
- **LR_AUTHENTICATED**: Long Range authenticated (Key Slot 3)
- **LR_ACCESS**: Long Range access (Key Slot 4)

**Cryptographic Primitives:**
- AES-128 (ECB and CBC modes)
- AES-CMAC for authentication
- Curve25519 ECDH for key exchange
- CTR-DRBG for random number generation
- NIST-approved key derivation

See [s2_security_architecture.puml](s2_security_architecture.puml) for detailed security architecture.

#### S2 Inclusion FSM (libs2/inclusion/s2_inclusion.c - 81 KB)
State machine for secure node inclusion using S2 protocol.

**Inclusion Phases:**
1. KEX (Key Exchange) Report/Get
2. Public key exchange (Curve25519 ECDH)
3. DSK verification (user-assisted or QR code)
4. Echo KEX exchange
5. Network key distribution
6. Network key verification
7. Transfer complete

**Timeouts:**
- Short operations: 10 seconds
- Long operations (user input): 240 seconds

See [s2_inclusion_fsm.puml](s2_inclusion_fsm.puml) for state diagram.

#### Transport Service 2 (libs2/transport_service/transport2_fsm.c)
Handles segmentation and reassembly of large Z-Wave frames.

**States:** 9 states
- ST_IDLE
- ST_RECEIVING / ST_SEND_FRAG_COMPLETE / ST_SEND_FRAG_REQ
- ST_SEND_FRAG_WAIT / ST_FIND_MISS_FRAG
- ST_SEND_FRAG / ST_SEND_LAST_FRAG / ST_WAIT_ACK

**Features:**
- Automatic fragmentation of large datagrams
- Missing fragment detection and retransmission
- CRC16 checksum verification
- Support for both singlecast and multicast

See [transport_service2_fsm.puml](transport_service2_fsm.puml) for state diagram.

#### Security Layer (src/security_layer.c - 16 KB)
Routes frames to appropriate security handlers (S0/S2).

#### Serial API (src/Serialapi.c - 119 KB)
Communication protocol with Z-Wave controller (NCP).

**Protocol:**
- UART-based binary protocol
- Frame acknowledgments
- Callback handling
- Network management commands
- Application commands

**Security Note**: Network keys are transmitted over unencrypted UART. Physical access protection is required.

### Tier 3: Networking

#### mDNS Service (src/mDNSService.c - 70 KB)
Provides service discovery for Z-Wave nodes on the IP network.

**Features:**
- Automatic node announcement
- Dynamic resource updates
- Device type information
- Command class advertising
- IPv6/IPv4 address publishing

#### IPv4/IPv6 Support
Dual-stack IP implementation with NAT support.

**IP Address Assignment:**
- IPv6: Prefix-based addressing (`fd00:aaaa::/48` default)
- IPv4: Virtual subnet addressing (`42.42.42.0/24` default)
- Automatic address assignment per node

## Data Flow

### Incoming Command Flow (LAN → PAN)

```
ZIP Client → [DTLS] → ZIP Router → Command Class Handler
                                         ↓
                                    Security Layer
                                         ↓
                               [S0/S2 Encryption]
                                         ↓
                                 Transport Service 2
                                   [Segmentation]
                                         ↓
                                    Serial API
                                         ↓
                               Z-Wave Controller (NCP)
                                         ↓
                                   Z-Wave Node
```

### Outgoing Report Flow (PAN → LAN)

```
Z-Wave Node → Z-Wave Controller → Serial API
                                       ↓
                               Transport Service 2
                                 [Reassembly]
                                       ↓
                                 Security Layer
                              [S0/S2 Decryption]
                                       ↓
                                  ZIP Router
                              [Frame Routing]
                                       ↓
                     ┌──────────────────┼──────────────────┐
                     ↓                  ↓                  ↓
              Addressed Client   Unsolicited Dest.    mDNS Update
```

## Security Architecture

### Security 2 (S2) Overview

S2 provides authenticated and encrypted communication using modern cryptography.

**Key Features:**
- Elliptic Curve Diffie-Hellman (ECDH) key exchange using Curve25519
- AES-128-CCM for authenticated encryption
- Device Specific Key (DSK) for device authentication
- Multiple security classes for different access levels
- Single-frame security (no frame splitting)
- SPAN table for replay protection

### S2 Key Management

**Key Storage:**
- Network keys stored in gateway persistent storage
- Per-node SPAN tables for nonce synchronization
- Key derivation using NIST SP 800-108

**Key Slots:**
```c
#define UNAUTHENTICATED_KEY_SLOT    0  // Basic S2
#define AUTHENTICATED_KEY_SLOT      1  // Authenticated S2
#define ACCESS_KEY_SLOT             2  // Access Control S2
#define LR_AUTHENTICATED_KEY_SLOT   3  // Long Range Auth
#define LR_ACCESS_KEY_SLOT          4  // Long Range Access
#define TEMP_KEY_SECURE             5  // Temporary inclusion key
#define NETWORK_KEY_SECURE          6  // Current network key
```

### S2 SPAN Table

Sequence Number (SPAN) table maintains nonce synchronization.

**Features:**
- Persisted on gateway shutdown
- Prevents replay attacks
- Automatic re-synchronization on desync
- S2_RESYNCHRONIZATION_EVENT notification

See [s2_key_management.puml](s2_key_management.puml) for key management flow.

## Network Management

### Node Inclusion Process

#### Classic Inclusion (S0)
1. Start add mode
2. Node sends Node Info Frame (NIF)
3. Protocol assigns NodeID
4. S0 key exchange (if secure)
5. Node interview (probing)
6. IPv4/IPv6 address assignment
7. mDNS announcement

#### S2 Inclusion
1. Start add mode (with S2 options)
2. Node sends NIF
3. Protocol assigns NodeID
4. **S2 Inclusion FSM:**
   - KEX Report (node capabilities)
   - Key grant decision
   - Public key exchange (ECDH)
   - DSK verification (user confirms first 5 digits)
   - Echo KEX
   - Network key distribution (per security class)
   - Network key verification
5. Node interview (probing)
6. IPv4/IPv6 address assignment
7. mDNS announcement

#### Smart Start Inclusion
1. Add DSK to provisioning list (via QR code)
2. Gateway enters Smart Start mode
3. Node broadcasts NWI (Network Wide Inclusion) request
4. Gateway matches DSK and accepts
5. S2 inclusion process (automatic)
6. On failure: Self-destruct mechanism removes node

See [node_inclusion_flow.puml](node_inclusion_flow.puml) for sequence diagram.

### Node Probing

The Resource Directory performs node interviews to gather capabilities.

**Probing Stages:**
1. **Node Info**: Basic node information
2. **Version CC**: Command class versions
3. **Endpoints**: Multi-channel endpoint discovery
4. **Security**: Security level detection

**Probing Triggers:**
- New node inclusion
- Node info update request
- Cache expiration
- Manual rediscovery

## State Machines

The gateway contains three major finite state machines:

### 1. Network Management State Machine (NMS)
- **States**: 30+
- **File**: src/CC_NetworkManagement.c
- **Purpose**: Orchestrates all network management operations

**Key State Groups:**
- Idle and ready states
- Add node states (classic, S2, Smart Start, proxy)
- Remove node states
- Learn mode states (inclusion/exclusion)
- Replace failed node states
- Self-destruct states (Smart Start failure handling)

See [network_management_fsm.puml](network_management_fsm.puml)

### 2. S2 Inclusion State Machine
- **States**: ~15 (Add mode) + ~10 (Learn mode)
- **File**: libs2/inclusion/s2_inclusion.c
- **Purpose**: Secure bootstrapping and key exchange

See [s2_inclusion_fsm.puml](s2_inclusion_fsm.puml)

### 3. Transport Service 2 State Machine
- **States**: 9
- **File**: libs2/transport_service/transport2_fsm.c
- **Purpose**: Frame fragmentation and reassembly

**State Groups:**
- Idle state
- Receive states (5)
- Send states (3)

See [transport_service2_fsm.puml](transport_service2_fsm.puml)

## Persistence

### Database Storage (SQLite)
- **File**: `zipgateway.db`
- **Contents**:
  - Resource Directory (node capabilities)
  - S2 SPAN tables
  - IP associations
  - Virtual node mappings
  - Mailbox queue

### NVM Storage (Z-Wave Controller)
- **Protocol data**: Maintained by Z-Wave controller
- **Network topology**: Routing tables, node lists
- **Security keys**: Stored in controller NVM

### Configuration Files
- **zipgateway.cfg**: Main configuration
- **provisioning_list.dat**: Smart Start provisioning list
- **DTLS certificates**: PSK or certificate-based

## Command Classes Supported

### LAN Side (ZIP)
| Command Class | Version | Purpose |
|--------------|---------|---------|
| Z/IP | 5 | Z-Wave over IP encapsulation |
| Z/IP Gateway | 1 | Gateway configuration |
| Z/IP ND | 2 | Neighbor discovery |
| Z/IP Naming | 1 | Node naming |
| Network Management Inclusion | 4 | Node inclusion/exclusion |
| Network Management Proxy | 4 | Proxy inclusion |
| Network Management Installation Maintenance | 4 | Network statistics |
| Node Provisioning | 1 | Smart Start provisioning |
| Mailbox | 2 | Non-listening node support |
| Security 2 | 1 | S2 security |
| Transport Service | 2 | Frame fragmentation |

### PAN Side (Z-Wave)
The gateway controls and understands:
- Association (v2)
- Multi Channel (v4)
- Multi Channel Association (v3)
- Security (v1)
- Security 2 (v1)
- Transport Service (v2)
- Wake Up (v2)
- And transparently forwards all other command classes

## Build System

### CMake Configuration
- **Minimum Version**: CMake 3.7+
- **Platform Detection**: Automatic (Linux, macOS, ARM)
- **Cross-Compilation**: 32-bit toolchain support
- **Testing**: CTest with Valgrind integration
- **Static Analysis**: cppcheck integration
- **Packaging**: CPack for Debian package generation

### Key Build Options
```cmake
-DDISABLE_DTLS=ON          # Disable DTLS for debugging
-DCMAKE_BUILD_TYPE=Debug   # Debug build
```

### Dependencies
- OpenSSL 1.1.0+ (DTLS/TLS)
- libusb 1.0 (USB communication)
- JSON-C (Configuration parsing)
- avahi (mDNS on Linux)

## Platform Support

### Hardware
- ARM (Raspberry Pi 3B+)
- MIPS big-endian (8devices Lima board)
- x86/x86_64 (with 32-bit compatibility)

### Software
- Debian 9 (Stretch) - Reference platform (EoL)
- Ubuntu 18.04
- OpenSSL 1.1.X

### Z-Wave Controller
- SDK 6.6x, 6.8x, 7.13+
- Serial API bridge firmware
- Minimum 32KB NVM

## Performance Considerations

### Resource Usage
- **RAM**: ~50-100 MB (depends on network size)
- **CPU**: Low (event-driven architecture)
- **Storage**: ~10-50 MB database (depends on network size)

### Limitations
- Maximum 2000 mailbox entries
- Maximum 232 Z-Wave nodes (classic) or 4000 (Long Range)
- 5-second timeout for most operations
- 240-second timeout for S2 inclusion with user interaction

## Deployment

### Standard Deployment
1. Install Z-Wave controller with Serial API firmware
2. Install zipgateway Debian package
3. Configure `/usr/local/etc/zipgateway.cfg`
4. Start systemd service: `systemctl start zipgateway`
5. Connect with reference_client

### Migration from Other Gateways
The gateway supports migration from other Z-Wave controllers:
1. Backup existing network to JSON format
2. Flash bridge controller firmware
3. Run zgw_restore tool
4. Start gateway

**Supported Migration Paths:**
- SDK 6.6x, 6.8x → 7.18.05
- 500-series → 700-series hardware
- 700-series → 800-series hardware

## Troubleshooting

### Logging
- **Gateway Log**: `/var/log/zipgateway.log`
- **Client Log**: Specified via `-g` parameter
- **Log Levels**: ERROR, WARN, INFO, DEBUG

### Common Issues
1. **Node inclusion fails**: Check security key configuration
2. **S2 timeout**: Ensure DSK verification within 240s
3. **SPAN desynchronization**: Check for power cycles or network issues
4. **Mailbox full**: Increase queue size or reduce traffic to sleeping nodes

## References

### Documentation Files
- [README.md](../README.md) - Setup and build instructions
- [RELEASE_NOTE.md](RELEASE_NOTE.md) - Version history and features
- [network_management_fsm.puml](network_management_fsm.puml) - NM state machine diagram
- [s2_inclusion_fsm.puml](s2_inclusion_fsm.puml) - S2 inclusion state machine
- [transport_service2_fsm.puml](transport_service2_fsm.puml) - Transport FSM
- [s2_security_architecture.puml](s2_security_architecture.puml) - S2 architecture

### External Resources
- [Z-Wave Specification](https://www.silabs.com/wireless/z-wave/specification)
- [Z-Wave Protocol Controller](https://github.com/SiliconLabsSoftware/z-wave-protocol-controller)
- [Silicon Labs Z-Wave Documentation](https://docs.silabs.com/z-wave/7.22.1/)

## Maintenance and Support

**Status**: Maintenance mode - critical fixes only

**Recommendation**: For new projects, migrate to the [z-wave-protocol-controller](https://github.com/SiliconLabsSoftware/z-wave-protocol-controller) project, which provides:
- Active development and support
- Latest Z-Wave protocol features
- Modern architecture
- Better documentation

**Support**: [Silicon Labs Support](http://www.silabs.com/support)
