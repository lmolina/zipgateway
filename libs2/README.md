Security 2 Command Class Implementation

This library implements the Z-Wave Security 2 (S2) command class, providing
authenticated encryption for Z-Wave communications using modern cryptography.

## Overview

S2 provides significant security improvements over the legacy S0 security:
- Elliptic Curve Diffie-Hellman (ECDH) key exchange using Curve25519
- Authenticated encryption with AES-128-CCM
- Multiple security classes for different access levels
- Device Specific Key (DSK) for device authentication
- Single-frame security (no frame splitting required)
- SPAN table for replay protection

## Security Classes

The library supports five security classes (key slots):
- **Slot 0**: S2_UNAUTHENTICATED - Basic encryption without authentication
- **Slot 1**: S2_AUTHENTICATED - Authenticated encryption with DSK verification
- **Slot 2**: S2_ACCESS - Highest security level for access control
- **Slot 3**: S2_LR_AUTHENTICATED - Long Range authenticated
- **Slot 4**: S2_LR_ACCESS - Long Range access control

## Directory Structure

```
libs2/
├── crypto/         Cryptographic primitives
│   ├── aes/        AES-128 implementation (ECB, CBC, CCM modes)
│   ├── curve25519/ Elliptic curve Diffie-Hellman
│   └── ctr_drbg/   NIST-approved random number generator
├── protocol/       S2 protocol implementation
│   └── S2.c        Main S2 protocol and state machines (52 KB)
├── inclusion/      S2 inclusion state machine
│   └── s2_inclusion.c  Secure node inclusion (81 KB)
├── transport_service/  Transport Service 2 (frame fragmentation)
├── test/           Unit tests with Unity framework
├── include/        Public header files and API
│   ├── s2_inclusion.h  S2 inclusion API
│   ├── S2.h            S2 protocol API
│   └── s2_keystore.h   Key management API
└── interface/      Protocol interfaces
```

## Key Components

### S2 Protocol (protocol/S2.c)
- Frame encryption and decryption using AES-CCM
- SPAN (Sequence Number) management for replay protection
- Nonce generation and validation
- Multi-key support for different security classes

### S2 Inclusion (inclusion/s2_inclusion.c)
- State machine for secure node inclusion (Add Mode and Learn Mode)
- ECDH key exchange using Curve25519
- DSK verification (user confirms first 5 digits)
- Network key distribution and verification
- Timeout handling (10s for protocol, 240s for user interaction)

### Cryptographic Primitives (crypto/)
- **AES**: AES-128 in ECB, CBC, and CCM modes
- **Curve25519**: Elliptic Curve Diffie-Hellman for key exchange
- **CTR-DRBG**: NIST SP 800-90A deterministic random bit generator
- **CMAC**: AES-CMAC for message authentication

## State Machines

The library implements complex finite state machines:

1. **S2 Inclusion FSM** - Handles secure bootstrapping
   - Add Mode: ~15 states (controller perspective)
   - Learn Mode: ~10 states (joining node perspective)
   - See: `/doc/s2_inclusion_fsm.puml` and `/doc/s2_learn_mode_fsm.puml`

2. **Transport Service 2 FSM** - Frame fragmentation
   - 9 states for segmentation and reassembly
   - See: `/doc/transport_service2_fsm.puml`

## Documentation

For detailed architecture and state machine documentation, see:
- `/doc/ARCHITECTURE.md` - Complete architecture overview
- `/doc/s2_security_architecture.puml` - S2 security architecture diagram
- `/doc/s2_inclusion_fsm.puml` - S2 inclusion state machine (Add Mode)
- `/doc/s2_learn_mode_fsm.puml` - S2 inclusion state machine (Learn Mode)
- `/doc/s2_key_management.puml` - S2 key lifecycle and management
- Doxygen documentation: Build with `make doc` in build directory

## Building

The S2 library is built as part of the main Z/IP Gateway build:

```bash
mkdir build
cd build
cmake ..
make
```

To build tests:
```bash
cd libs2
mkdir build
cd build
cmake ..
make
make test
```

## Testing

Unit tests use the Unity test framework:
- `test/` - S2 protocol tests
- `inclusion/test/` - S2 inclusion tests
- `TestFramework/` - Unity test framework and mocks

Run tests with:
```bash
cd build
make test
# or with Valgrind for memory leak detection
ctest -T memcheck
```

## API Usage

### Inclusion (Controller Side)
```c
// Set event handler
s2_inclusion_set_event_handler(my_event_handler);

// Start inclusion
s2_inclusion_including_start(p_context);

// When KEX Report event received, grant keys
s2_inclusion_key_grant(p_context, 1, keys, csa_flag);

// When Public Key Challenge event received, verify DSK
s2_inclusion_challenge_response(p_context, 1, dsk, dsk_len);
```

### Encryption/Decryption
```c
// Encrypt a frame
uint8_t encrypted_frame[256];
uint16_t encrypted_len = S2_encrypt_frame(
    p_context,
    plaintext, plaintext_len,
    encrypted_frame, sizeof(encrypted_frame),
    security_class
);

// Decrypt a frame
uint8_t plaintext[256];
uint16_t plaintext_len = S2_decrypt_frame(
    p_context,
    encrypted_frame, encrypted_len,
    plaintext, sizeof(plaintext)
);
```

## Security Considerations

**Key Storage**: Network keys are stored in plain text in the keystore. Ensure
proper file system permissions and consider full-disk encryption.

**SPAN Persistence**: The SPAN table MUST be persisted across reboots to
prevent replay attacks. The gateway handles this automatically.

**Physical Security**: Keys are transmitted over UART (unencrypted) to the
Z-Wave controller during initialization. Physical access protection is required.

**DSK Verification**: Always verify the DSK during inclusion to prevent
man-in-the-middle attacks. The user must confirm the first 5 digits.

## References

- Z-Wave Security 2 Command Class Specification (SDS13783)
- NIST SP 800-108: Key Derivation Functions
- NIST SP 800-90A: Random Number Generation
- RFC 7748: Elliptic Curves for Security (Curve25519)
- NIST SP 800-38C: CCM Mode (Counter with CBC-MAC)

