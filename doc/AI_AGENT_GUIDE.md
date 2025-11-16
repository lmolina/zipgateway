# AI Agent Guide - Z/IP Gateway

**Quick reference for AI assistants working with this codebase**

## TL;DR for AI Agents

```yaml
Project: Z/IP Gateway v7.18.05
Status: Maintenance mode (critical fixes only)
Successor: https://github.com/SiliconLabsSoftware/z-wave-protocol-controller
Language: C
Build: CMake 3.7+
Architecture: 3-tier (Gateway Core → Security/Transport → Networking)
Key Complexity: Network Management FSM (30+ states), S2 Security
```

## Quick File Lookup

### Need to understand...
| Topic | Primary File | Lines | Alt File |
|-------|-------------|-------|----------|
| Overall architecture | `doc/ARCHITECTURE.md` | - | `doc/architecture-metadata.yaml` |
| Network management FSM | `src/CC_NetworkManagement.c` | 3420 | `src/CC_NetworkManagement.h` |
| S2 security protocol | `libs2/protocol/S2.c` | 52KB | `libs2/include/S2.h` |
| S2 inclusion (pairing) | `libs2/inclusion/s2_inclusion.c` | 81KB | `libs2/include/s2_inclusion.h` |
| Node database | `src/ResourceDirectory.c` | 2930 | `src/ResourceDirectory.h` |
| Main event loop | `src/ZIP_Router.c` | 1813 | - |
| Serial protocol | `src/Serialapi.c` | 119KB | - |
| Frame fragmentation | `libs2/transport_service/transport2_fsm.c` | - | `libs2/transport_service/transport2_fsm.h` |
| Key management | `src/S2_wrap.c` | 27KB | `libs2/include/s2_keystore.h` |

### Visual Diagrams (PlantUML)
| Diagram | Shows | States/Components |
|---------|-------|-------------------|
| `doc/architecture_overview.puml` | Full architecture | 3 tiers, 15+ components |
| `doc/network_management_fsm.puml` | Network Mgmt FSM | 30+ states |
| `doc/s2_inclusion_fsm.puml` | S2 pairing (controller) | ~15 states |
| `doc/s2_learn_mode_fsm.puml` | S2 pairing (joining node) | ~10 states |
| `doc/transport_service2_fsm.puml` | Frame fragmentation | 9 states |
| `doc/s2_security_architecture.puml` | S2 crypto stack | - |
| `doc/component_interactions.puml` | Sequence diagrams | Multiple flows |

## State Machine Quick Reference

### Network Management States (30+)
```
Idle: NM_IDLE, NM_WAITING_FOR_PROBE
Add: NM_WAIT_FOR_ADD → NM_NODE_FOUND → NM_WAIT_FOR_SECURE_ADD → NM_WAIT_FOR_PROBE_AFTER_ADD → NM_WAIT_DHCP
Remove: NM_WAITING_FOR_NODE_REMOVAL → NM_REMOVING_ASSOCIATIONS
Learn: NM_LEARN_MODE → NM_LEARN_MODE_STARTED → NM_WAIT_FOR_SECURE_LEARN → NM_WAIT_FOR_MDNS
Smart Start Failure: NM_WAIT_FOR_SELF_DESTRUCT → ... → NM_WAIT_FOR_SELF_DESTRUCT_REMOVAL
```
**File**: `src/CC_NetworkManagement.h:89-413`

### S2 Inclusion States (~15 Add Mode, ~10 Learn Mode)
```
Add Mode: Idle → Wait KEX Report → Wait User Accept → Wait Public Key →
          Wait DSK User → Wait Echo KEX → Wait Net Key Get →
          Wait Net Key Verify → Wait Transfer End → Idle
```
**File**: `libs2/inclusion/s2_inclusion.c`

### Transport Service 2 States (9)
```
Receive: ST_IDLE → ST_RECEIVING → ST_FIND_MISS_FRAG → ST_SEND_FRAG_COMPLETE
Send: ST_IDLE → ST_SEND_FRAG → ST_SEND_LAST_FRAG → ST_WAIT_ACK
```
**File**: `libs2/transport_service/transport2_fsm.h:13-28`

## Common Code Patterns

### Adding a new network management operation
1. Add state(s) to `nm_state_t` enum in `src/CC_NetworkManagement.h`
2. Add event(s) to `nm_event_t` enum
3. Implement state handler in `src/CC_NetworkManagement.c`
4. Update state transition table
5. Update `doc/network_management_fsm.puml`

### S2 encryption/decryption
```c
// Encrypt
S2_encrypt_frame(context, plaintext, len, encrypted_buf, buf_size, security_class);

// Decrypt
S2_decrypt_frame(context, encrypted, len, plaintext_buf, buf_size);
```
**File**: `libs2/protocol/S2.c`

### Checking node security class
```c
// Get granted keys for a node
uint8_t granted_keys = keystore_network_key_read(node_id, &key_class);
```
**File**: `libs2/include/s2_keystore.h`

## Security Classes (Key Slots)

| Slot | Name | Security Level | Usage |
|------|------|----------------|-------|
| 0 | S2_UNAUTHENTICATED | Low | Basic encryption, no auth |
| 1 | S2_AUTHENTICATED | Medium | DSK-authenticated |
| 2 | S2_ACCESS | High | Access control |
| 3 | S2_LR_AUTHENTICATED | Medium | Long Range auth |
| 4 | S2_LR_ACCESS | High | Long Range access |
| 5 | TEMP_KEY | - | Temporary (inclusion) |
| 6 | NETWORK_KEY | - | Current network key |

**File**: `libs2/inclusion/s2_inclusion_internal.h:8-19`

## Critical Timeouts

| Operation | Timeout | Constant |
|-----------|---------|----------|
| Add/Remove node | 6s | `ADD_REMOVE_TIMEOUT` |
| Learn mode | 6s | `LEARN_TIMEOUT` |
| S2 protocol operation | 10s | (in S2 code) |
| S2 user interaction (DSK) | 240s | (in S2 code) |
| Smart Start self-destruct | 3s | `SMART_START_SELF_DESTRUCT_TIMEOUT` |
| Smart Start retry | 240s | `SMART_START_SELF_DESTRUCT_RETRY_TIMEOUT` |

**File**: `src/CC_NetworkManagement.c:35-40`

## Data Flow Cheat Sheet

### Encrypted command (Client → Node)
```
ZIP Client → ZIP Router → Security Layer → S2 Protocol (encrypt) →
Transport Service 2 (fragment) → Serial API → NCP → Z-Wave Node
```

### Report (Node → Client)
```
Z-Wave Node → NCP → Serial API → Transport Service 2 (reassemble) →
S2 Protocol (decrypt, verify SPAN) → Security Layer → ZIP Router → ZIP Client
```

### S2 Inclusion Flow
```
1. Controller sends KEX Get
2. Node sends KEX Report (capabilities)
3. User grants keys → Controller sends KEX Set
4. ECDH: Exchange public keys → Compute shared secret
5. User verifies DSK (first 5 digits)
6. Controller sends Echo KEX → Node echoes
7. For each security class:
   - Node: Net Key Get
   - Controller: Net Key Report (encrypted with KEK)
   - Node: Net Key Verify (proves decryption)
8. Transfer End → Inclusion complete
```

## Common Debugging Points

### Node won't include
1. Check logs: `/var/log/zipgateway.log`
2. Check NM state: Look for state transitions in log
3. Check S2 events: KEX Report, Public Key, DSK, Transfer End
4. Timeout? Check if 240s exceeded for DSK verification
5. Check security keys in keystore

### S2 decryption fails
1. Check SPAN table: May be out of sync
2. Look for "Nonce Report SOS=1" in logs (re-sync)
3. Verify correct security class
4. Check if network key matches

### Memory leak
```bash
cd build
ctest -T memcheck  # Valgrind integration
```

### State machine stuck
1. Find current state in logs
2. Check timeout timers
3. Look for missing event triggers
4. Check if external dependency (e.g., protocol callback) failed

## Structured Data for Parsing

See `doc/architecture-metadata.yaml` for machine-readable architecture data:
- Component registry with dependencies
- State machine definitions
- Data flow specifications
- Security threat model
- Performance characteristics

## Code Navigation Tips

### Finding a state handler
```bash
# Network Management
grep -n "case NM_WAIT_FOR_ADD:" src/CC_NetworkManagement.c

# S2 Inclusion
grep -n "S2_AWAITING_KEX_REPORT" libs2/inclusion/s2_inclusion.c
```

### Finding where an event is posted
```bash
grep -rn "nm_fsm_post_event(NM_EV_SECURITY_DONE" src/
```

### Finding all uses of a component
```bash
grep -rn "s2_inclusion_" src/ libs2/
```

## Testing

```bash
# Build with tests
mkdir build && cd build
cmake .. && make

# Run all tests
make test

# Run specific test
./test/ZIP_router/test_ZIP_router

# Memory leak check
ctest -T memcheck

# Static analysis
cppcheck --enable=all ../src/
```

## When Making Changes

### Checklist
- [ ] Update code
- [ ] Update relevant state machine diagram (`.puml`)
- [ ] Update `ARCHITECTURE.md` if architecture changed
- [ ] Update `architecture-metadata.yaml` if component/state added
- [ ] Update Doxygen comments
- [ ] Add/update tests
- [ ] Run `make test` and `ctest -T memcheck`
- [ ] Update `RELEASE_NOTE.md` if user-facing

### Documentation Sync
If you change:
- **States**: Update `.puml` diagram + `architecture-metadata.yaml` + `ARCHITECTURE.md`
- **Components**: Update `architecture-metadata.yaml` + `ARCHITECTURE.md`
- **Timeouts**: Update `architecture-metadata.yaml` + code comments
- **Security**: Update S2 docs + `architecture-metadata.yaml`

## Quick Answers for Common Questions

**Q: What's the main entry point?**
A: `src/ZW_ZIPApplication.c:ApplicationInit()` → `ZIP_Router_Init()`

**Q: Where are network keys stored?**
A: SQLite database (`zipgateway.db`) in plaintext. Physical security required.

**Q: How does Smart Start work?**
A: DSK added to provisioning list → Node broadcasts NWI → Gateway matches DSK → Auto S2 inclusion

**Q: What's SPAN?**
A: Sequence Number table for replay protection. Must persist across reboots.

**Q: Why 240s timeout?**
A: S2 inclusion requires user to verify DSK (first 5 digits). Allows time for user interaction.

**Q: Can I run on 64-bit?**
A: Only with 32-bit compatibility libraries. Native 64-bit not supported.

**Q: What's the difference between S0 and S2?**
A: S2 uses modern crypto (ECDH, AES-CCM), has multiple security classes, and better performance.

**Q: How to migrate from another gateway?**
A: Use `zgw_restore` tool with JSON backup. See `systools/doc/README.md`

## AI-Specific Hints

When analyzing this codebase:
- **Complex FSMs**: Focus on state transitions, not implementation details
- **Security critical**: S2 key exchange, SPAN table, keystore
- **Event-driven**: Follow event posting/handling chains
- **Multi-layer**: Gateway Core ↔ Security/Transport ↔ Networking
- **Legacy code**: Some patterns are historical, not best practice
- **Maintenance mode**: Don't suggest major refactorings

**Parse order for fastest understanding**:
1. `doc/architecture-metadata.yaml` (structured data)
2. `doc/ARCHITECTURE.md` (text overview)
3. `doc/architecture_overview.puml` (visual)
4. Specific component files as needed

---

**Last updated**: 2025-11-09 (aligned with v7.18.05)
