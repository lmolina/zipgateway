# Z/IP Gateway Documentation Index

This document provides an index of all architecture and technical documentation for the Z/IP Gateway project.

## Core Documentation

### Architecture
- **[ARCHITECTURE.md](ARCHITECTURE.md)** - Comprehensive architecture overview
  - Three-tier architecture explanation
  - Component descriptions
  - Data flow diagrams (text-based)
  - Security architecture overview
  - Build system and deployment

### Release Information
- **[RELEASE_NOTE.md](RELEASE_NOTE.md)** - Version 7.18.05 release notes
  - Improvements and fixed issues
  - Known issues
  - Feature descriptions
  - Platform requirements
  - Migration notes

### Setup and Usage
- **[README.md](../README.md)** - Getting started guide
  - Installation instructions
  - Build instructions
  - Basic usage examples
  - Dependencies

## PlantUML Diagrams

### Architecture Diagrams
- **[architecture_overview.puml](architecture_overview.puml)** - High-level component architecture
  - Three-tier layered architecture
  - Component relationships
  - Data flow between tiers
  - External interfaces

- **[component_interactions.puml](component_interactions.puml)** - Component interaction sequences
  - Node inclusion flow
  - Encrypted command flow
  - Large frame fragmentation
  - Mailbox operations
  - mDNS announcements
  - SPAN re-synchronization

### State Machine Diagrams
- **[network_management_fsm.puml](network_management_fsm.puml)** - Network Management FSM (30+ states)
  - Node addition states (classic, S2, Smart Start)
  - Node removal states
  - Learn mode states
  - Replace failed node states
  - Smart Start self-destruct flow
  - Proxy inclusion

- **[transport_service2_fsm.puml](transport_service2_fsm.puml)** - Transport Service 2 FSM (9 states)
  - Receive state machine (5 states)
  - Send state machine (3 states)
  - Fragment reassembly
  - Missing fragment handling
  - ACK and retransmission

- **[s2_inclusion_fsm.puml](s2_inclusion_fsm.puml)** - S2 Inclusion FSM (Add Mode)
  - KEX (Key Exchange) states
  - ECDH public key exchange
  - DSK verification
  - Network key distribution
  - Security class handling

- **[s2_learn_mode_fsm.puml](s2_learn_mode_fsm.puml)** - S2 Inclusion FSM (Learn Mode)
  - Joining node perspective
  - Controller DSK verification
  - Key reception flow
  - Differences from Add Mode

### Security Diagrams
- **[s2_security_architecture.puml](s2_security_architecture.puml)** - S2 security architecture
  - Cryptographic primitives (AES-CCM, Curve25519)
  - Security classes (Unauthenticated, Authenticated, Access)
  - Key slots and management
  - SPAN table for replay protection
  - Encryption/decryption flows

- **[s2_key_management.puml](s2_key_management.puml)** - S2 key lifecycle
  - Key generation
  - ECDH key exchange during inclusion
  - Key storage and persistence
  - SPAN table management
  - Encryption/decryption with key usage
  - Re-synchronization flow

### Legacy Diagrams
- **[mailbox_sequence.plant](mailbox_sequence.plant)** - Mailbox proxy frame flow
- **[mailbox_sequence_client_offline.plant](mailbox_sequence_client_offline.plant)** - Client offline scenario
- **[mailbox_sequence_failing.plant](mailbox_sequence_failing.plant)** - Mailbox failure scenario
- **[mailbox_qf.plant](mailbox_qf.plant)** - Mailbox queue flow
- **[mailbox_timeout.plant](mailbox_timeout.plant)** - Mailbox timeout handling
- **[firmware.sm](firmware.sm)** - Firmware update state machine (SMC format)

## Source Code Documentation (Doxygen)

The project uses Doxygen for API documentation generation:

### Gateway Core
- **src/doc/** - Main gateway Doxygen configuration
  - [main.dox.in](../src/doc/main.dox.in) - Main documentation page
  - [groups.dox](../src/doc/groups.dox) - Documentation groups
  - [backup_restore.dox](../src/doc/backup_restore.dox) - Backup/restore documentation
  - [nms.gv](../src/doc/nms.gv) - Network management state diagram (GraphViz)
  - [nodeadd.gv](../src/doc/nodeadd.gv) - Node addition flow (GraphViz)
  - [ep-probe.gv](../src/doc/ep-probe.gv) - Endpoint probing (GraphViz)
  - [nms_add_mode.dox](../src/doc/nms_add_mode.dox) - Add mode documentation
  - [nms_learn_mode.dox](../src/doc/nms_learn_mode.dox) - Learn mode documentation
  - [rd_probe1_node.dox](../src/doc/rd_probe1_node.dox) - Resource directory node probing
  - [rd_probe2_ep.dox](../src/doc/rd_probe2_ep.dox) - Resource directory endpoint probing
  - [rd_cc_version_probe.dox](../src/doc/rd_cc_version_probe.dox) - CC version probing
  - [zgw_data.dox](../src/doc/zgw_data.dox) - Gateway data structures

### libzwaveip Documentation
- **libzwaveip/doc/** - Z-Wave IP library documentation
  - [main.dox.in](../libzwaveip/doc/main.dox.in) - Library overview

### libs2 Documentation
- **libs2/doc/** - S2 security library documentation
  - [main.dox.in](../libs2/doc/main.dox.in) - S2 library overview
  - Includes Doxygen diagrams for S2 inclusion state machines

### System Tools Documentation
- **systools/doc/** - System tools documentation
  - [README.md](../systools/doc/README.md) - Backup/restore and migration tools
  - [migration.dox.in](../systools/doc/migration.dox.in) - Migration process
  - JSON schemas for backup/restore formats

## Platform-Specific Documentation

- **[README.raspberry_pi](../README.raspberry_pi)** - Raspberry Pi specific setup
- **[README.udp_relays](../README.udp_relays)** - UDP relay configuration
- **[src/ReadMeWin32.txt](../src/ReadMeWin32.txt)** - Windows build notes (historical)

## Build Documentation

- **[libzwaveip/documentation/Build-osx-ubuntu.md](../libzwaveip/documentation/Build-osx-ubuntu.md)** - macOS and Ubuntu build
- **[libzwaveip/documentation/Build-doxygen-documentation.md](../libzwaveip/documentation/Build-doxygen-documentation.md)** - Building Doxygen docs
- **[libzwaveip/documentation/Using-the-Example-Applications.md](../libzwaveip/documentation/Using-the-Example-Applications.md)** - Example usage

## Key Source Files

For detailed implementation understanding, refer to these key source files:

### Core Components
- **src/ZIP_Router.c** (1,813 lines) - Main event dispatcher and router
- **src/CC_NetworkManagement.c** (3,420 lines) - Network management FSM implementation
- **src/CC_NetworkManagement.h** - Network management FSM states and events definitions
- **src/ResourceDirectory.c** (2,930 lines) - Node database and probing
- **src/Bridge.c** - IP emulation and virtual nodes
- **src/Mailbox.c** - Command queueing for sleeping nodes

### Security & Transport
- **libs2/protocol/S2.c** (52 KB) - S2 protocol implementation
- **libs2/inclusion/s2_inclusion.c** (81 KB) - S2 inclusion FSM implementation
- **libs2/include/s2_inclusion.h** - S2 inclusion API and documentation
- **libs2/inclusion/s2_inclusion_internal.h** - S2 key slot definitions
- **libs2/transport_service/transport2_fsm.c** - Transport Service 2 FSM
- **libs2/transport_service/transport2_fsm.h** - Transport Service 2 states/events
- **src/security_layer.c** (16 KB) - S0/S2 routing
- **src/S2_wrap.c** (27 KB) - S2 gateway integration

### Networking
- **src/mDNSService.c** (70 KB) - Service discovery
- **src/Serialapi.c** (119 KB) - Serial API protocol with Z-Wave controller

### Cryptography
- **libs2/crypto/aes/** - AES implementation
- **libs2/crypto/curve25519/** - ECDH implementation
- **libs2/crypto/ctr_drbg/** - Random number generation

## Viewing PlantUML Diagrams

To view the PlantUML diagrams, you have several options:

### Option 1: Online Viewer
1. Visit http://www.plantuml.com/plantuml/uml/
2. Copy and paste the diagram content
3. View the rendered diagram

### Option 2: VS Code Extension
1. Install "PlantUML" extension in VS Code
2. Open any `.puml` file
3. Press `Alt+D` to preview

### Option 3: Command Line
```bash
# Install PlantUML
sudo apt-get install plantuml graphviz

# Generate PNG from PlantUML file
plantuml architecture_overview.puml

# Generate SVG (scalable)
plantuml -tsvg architecture_overview.puml
```

### Option 4: IDE Integration
- **IntelliJ IDEA**: Install PlantUML Integration plugin
- **Eclipse**: Install PlantUML plugin
- **Atom**: Install plantuml-viewer package

## Documentation Generation

### Doxygen Documentation
To generate HTML documentation from Doxygen comments:

```bash
# For main gateway documentation
cd build
make doc

# For libs2 documentation
cd libs2/build
make doc

# For libzwaveip documentation
cd libzwaveip/build
make doc
```

Generated documentation will be in `build/doc/html/index.html`

## Contributing to Documentation

When updating documentation:

1. **Architecture Changes**: Update `ARCHITECTURE.md` and relevant PlantUML diagrams
2. **State Machine Changes**: Update corresponding `.puml` state machine diagrams
3. **API Changes**: Update Doxygen comments in source files
4. **New Features**: Update `RELEASE_NOTE.md` and add to architecture docs

## Documentation Maintenance

**Last Updated**: 2025-11-09
**Version**: 7.18.05
**Maintenance Status**: Critical fixes only

For the actively maintained successor project, see:
https://github.com/SiliconLabsSoftware/z-wave-protocol-controller

## Quick Reference

| Topic | Document | Type |
|-------|----------|------|
| Getting Started | README.md | Markdown |
| Architecture Overview | ARCHITECTURE.md | Markdown |
| High-Level Components | architecture_overview.puml | PlantUML |
| Network Management FSM | network_management_fsm.puml | PlantUML |
| S2 Security | s2_security_architecture.puml | PlantUML |
| S2 Inclusion | s2_inclusion_fsm.puml | PlantUML |
| Transport Service | transport_service2_fsm.puml | PlantUML |
| Component Interactions | component_interactions.puml | PlantUML |
| S2 Key Management | s2_key_management.puml | PlantUML |
| Release Notes | RELEASE_NOTE.md | Markdown |
| System Tools | systools/doc/README.md | Markdown |
| API Reference | Generated by Doxygen | HTML |

## External References

- [Z-Wave Specification](https://www.silabs.com/wireless/z-wave/specification)
- [Z-Wave Protocol Controller (Successor)](https://github.com/SiliconLabsSoftware/z-wave-protocol-controller)
- [Silicon Labs Z-Wave Documentation](https://docs.silabs.com/z-wave/7.22.1/)
- [Silicon Labs Support](http://www.silabs.com/support)
- [Z-Wave Alliance](https://z-wavealliance.org/)
