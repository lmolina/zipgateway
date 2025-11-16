# Z/IP Gateway: OS Suspend/Resume Impact Analysis

## Executive Summary

This document analyzes the impact of operating system suspend/resume cycles on the Z/IP Gateway application. The analysis reveals that **Z/IP Gateway is currently NOT designed to handle OS suspend/resume** and will experience critical failures when the OS suspends while the Z-Wave network and controller module continue to operate.

**Key Finding:** The Z/IP Gateway uses a single-threaded, event-driven architecture (Contiki OS) with persistent serial communication, software-based timers, and stateful network connections. When the OS suspends, all software execution halts while the Z-Wave controller module continues operating, creating severe state desynchronization.

**Risk Level:** **CRITICAL** - High probability of complete service disruption requiring full gateway restart.

---

## System Architecture Overview

### Z/IP Gateway Architecture
- **Operating System:** Contiki OS (event-driven, cooperative multitasking)
- **Concurrency Model:** Single-threaded with protothreads (stackless coroutines)
- **Timer Implementation:** Software timers based on `CLOCK_MONOTONIC_RAW`
- **Serial Communication:** UART at 115200 baud, persistent file descriptor
- **Network:** UDP/DTLS sockets for Z/IP protocol, TCP for portal tunnel
- **Persistence:** SQLite database for resource directory and S2 security state

### Controller Module Communication
- **Interface:** Serial API over UART (`/dev/ttyUSB0`, `/dev/ttyACM0`)
- **Protocol:** Frame-based binary protocol (SOF/Length/Type/Cmd/Data/Checksum)
- **Timing:** ACK timeout 150ms, RX timeout 150ms, TX retransmission on timeout
- **Watchdog:** Periodic kick required for Gecko (700/800 series) chips
- **State:** Controller maintains network topology, routing tables, and security keys in NVM

### Key Components
1. **Serial API Process** (`src/serialapi/Serialapi.c`) - Manages controller communication
2. **Contiki Processes** - 8+ concurrent protothreads (ZIP, DTLS, UDP, mDNS, etc.)
3. **Network Management FSM** - 30+ states for inclusion/exclusion operations
4. **Resource Directory** - SQLite-based node capability database
5. **Packet Queues** - First attempt and long queues with timeout management
6. **S2 Security** - DTLS sessions and SPAN nonce tracking

---

## Impact on Controller Host (OS/Application)

### Issue 1: Serial Port Communication Disruption

**Description:**
The serial port file descriptor (`serial_fd`) to the Z-Wave controller remains open during OS suspend. When the OS suspends, the serial port driver state may be altered, and buffered data may be lost. The UART hardware state (termios settings) may not be preserved.

**Technical Details:**
- File descriptor opened in `linux-serial.c:OpenSerialPort()` at line 53
- Uses blocking I/O with `select()` for polling in `SerialCheck()` at line 236
- Termios settings: 115200 baud, 8N1, no flow control (line 76-83)
- Serial protocol state machine in `conhandle.c` tracks frame parsing state

**Impact Severity:** **CRITICAL**

**Failure Scenarios:**
1. File descriptor becomes invalid (OS reassigns /dev/ttyUSB0 on resume)
2. UART driver loses termios configuration
3. RX/TX buffers contain stale or corrupted data
4. Serial protocol state machine stuck in mid-frame parsing
5. ACK/NAK synchronization lost with controller

**Risk Assessment:**
- **Probability:** 95% - Serial port state loss is highly likely
- **Impact:** Complete loss of controller communication
- **Detection Time:** Immediate (first serial read/write attempt fails)
- **Recovery:** Requires full serial port reinitialization

**Proposed Solutions:**

**Solution 1: Graceful Serial Disconnect/Reconnect**
- **Approach:** Close serial port before suspend, reopen on resume
- **Implementation Steps:**
  1. Detect suspend via D-Bus signal (`PrepareForSleep` from systemd)
  2. Flush pending serial data with `tcdrain()`
  3. Send final ACK to controller
  4. Close serial port with `SerialClose()`
  5. On resume, call `SerialRestart()` (already exists at `linux-serial.c:126`)
  6. Re-verify controller communication with `FUNC_ID_SERIAL_API_GET_CAPABILITIES`
  7. Validate HomeID and NodeID unchanged
- **Pros:** Clean state transition, uses existing code
- **Cons:** Brief communication outage (1-2 seconds)
- **Risk Mitigation:** Controller may reset if watchdog not kicked (see Issue 8)

**Solution 2: Serial Port State Preservation**
- **Approach:** Preserve serial port state across suspend/resume
- **Implementation Steps:**
  1. Before suspend: Save termios settings with `tcgetattr()`
  2. Save current protocol state (frame parser state, pending ACK status)
  3. After resume: Reopen serial port
  4. Restore termios settings with `tcsetattr(TCSANOW, &saved_options)`
  5. Flush stale buffers with `tcflush(TCIOFLUSH)`
  6. Reset protocol state machine to `stateSOFHunt`
  7. Send ACK to synchronize
- **Pros:** Faster recovery, no controller reset needed
- **Cons:** Complex state preservation, stale data in buffers
- **Risk Mitigation:** May not handle device reassignment (e.g., /dev/ttyUSB0 → /dev/ttyUSB1)

**Solution 3: Kernel-Level Suspend Inhibition**
- **Approach:** Prevent OS suspend while critical operations are active
- **Implementation Steps:**
  1. Use systemd inhibitor locks: `systemd-inhibit --what=sleep`
  2. Acquire inhibitor lock during:
     - Active S2 inclusion (ECDH key exchange in progress)
     - Firmware update transfers
     - Network topology discovery
     - Backup/restore operations
  3. Release lock when returning to idle state
  4. Set maximum inhibit duration (e.g., 5 minutes) with timeout
- **Pros:** Prevents corruption during critical operations
- **Cons:** Doesn't solve the general case, may annoy users if suspend is blocked
- **Risk Mitigation:** Combine with Solution 1 for non-critical suspend scenarios

---

### Issue 2: Timer Desynchronization

**Description:**
All software timers in Z/IP Gateway are based on `CLOCK_MONOTONIC_RAW` which continues counting during suspend. When the application resumes, all timer comparisons will be incorrect, causing timeouts to either fire immediately or never fire at all.

**Technical Details:**
- Clock implementation in `contiki/platform/linux/clock.c:52-68`
- Uses `clock_gettime(CLOCK_MONOTONIC_RAW)` returning milliseconds since boot
- Event timers (`etimer`), callback timers (`ctimer`), and simple timers all affected
- Timer checks compare current `clock_time()` against stored future timestamps

**Impact Severity:** **CRITICAL**

**Failure Scenarios:**
1. All pending timers expire immediately (timestamp in past)
2. Queue timeout triggers prematurely, dropping valid packets
3. S2 inclusion timeout fires incorrectly (240 second timeout)
4. Mailbox NAK waiting timer (60 seconds) expires
5. Backup check timer (3 seconds) runs continuously
6. Serial ACK/RX timeouts (150ms) behave unpredictably

**Risk Assessment:**
- **Probability:** 100% - All timers will be affected
- **Impact:** Complete disruption of timed operations, potential packet loss
- **Detection Time:** Immediate on first timer check
- **Recovery:** Requires timer recalculation or full restart

**Proposed Solutions:**

**Solution 1: Monotonic Clock Offset Adjustment**
- **Approach:** Record clock offset before suspend and adjust all timers on resume
- **Implementation Steps:**
  1. Before suspend: Save `suspend_clock_offset = clock_time()`
  2. Before suspend: Save `suspend_wall_time = time(NULL)` (real-time clock)
  3. After resume: Calculate `resume_clock_offset = clock_time()`
  4. Calculate `suspend_duration = resume_clock_offset - suspend_clock_offset`
  5. Iterate all active timers and add `suspend_duration` to their expiry times:
     - `etimer_adjust(struct etimer *et, clock_time_t suspend_duration)`
     - `ctimer_adjust(struct ctimer *ct, clock_time_t suspend_duration)`
  6. Adjust global timer variables (e.g., `queue_timer`, `zgw_bu_timer`)
- **Pros:** Preserves relative timing, no timer loss
- **Cons:** Requires tracking all active timers, complex implementation
- **Risk Mitigation:** Long-running timers may expire during multi-hour suspends

**Solution 2: Timer Cancellation and Restart**
- **Approach:** Cancel all timers on suspend, restart them on resume
- **Implementation Steps:**
  1. Before suspend: Iterate all Contiki processes
  2. Call `process_post(PROCESS_SUSPEND, NULL)` to notify processes
  3. Each process cancels its timers in suspend handler
  4. After resume: Call `process_post(PROCESS_RESUME, NULL)`
  5. Each process restarts timers with original durations
  6. For queue timers, recalculate timeout based on original send time
- **Pros:** Clean state, well-defined semantics
- **Cons:** Requires modifying all processes, may lose timeout context
- **Risk Mitigation:** Short-duration operations may timeout incorrectly

**Solution 3: Use CLOCK_BOOTTIME Instead**
- **Approach:** Switch from `CLOCK_MONOTONIC_RAW` to `CLOCK_BOOTTIME`
- **Implementation Steps:**
  1. Modify `contiki/platform/linux/clock.c:56` to use `CLOCK_BOOTTIME`
  2. `CLOCK_BOOTTIME` includes suspend time (monotonic + suspend duration)
  3. All timer comparisons will automatically account for suspend
  4. No application-level changes needed
- **Pros:** Automatic handling, minimal code changes, standard Linux solution
- **Cons:** Timers that should pause during suspend will continue counting
- **Risk Mitigation:** May cause delayed operations to fire immediately on resume (e.g., 3-second backup check fires after 10-hour suspend)

---

### Issue 3: Network Socket Disruption

**Description:**
Z/IP Gateway maintains multiple open network sockets (UDP, DTLS, TCP, mDNS). During suspend, network interfaces may go down, DHCP leases may expire, and socket buffers may overflow with unprocessed packets.

**Technical Details:**
- UDP socket on port 41230 for Z/IP packets (`udp_server_process`)
- DTLS socket on port 4123 for secure Z/IP (`dtls_server_process`)
- TCP socket for portal tunnel (`zip_tcp_client_process`)
- mDNS multicast sockets for service discovery (`mDNS_server_process`)
- DHCP client for IPv4 address assignment (`dhcp_client_process`)

**Impact Severity:** **HIGH**

**Failure Scenarios:**
1. Network interface goes down during suspend (WiFi disconnects)
2. DHCP IPv4 lease expires, address reassigned to another device
3. Socket buffers overflow with unprocessed Z-Wave messages from network
4. DTLS sessions timeout (session cache expires)
5. mDNS service announcements missed, gateway disappears from discovery
6. TCP portal connection dropped by server timeout

**Risk Assessment:**
- **Probability:** 80% - Network disruption likely on WiFi, less on Ethernet
- **Impact:** Loss of LAN connectivity, manual reconnection required
- **Detection Time:** Variable (depends on socket operation)
- **Recovery:** May require full network stack restart

**Proposed Solutions:**

**Solution 1: Socket Graceful Shutdown/Restart**
- **Approach:** Close sockets before suspend, reopen on resume
- **Implementation Steps:**
  1. Before suspend: Post `PROCESS_SUSPEND` event to all network processes
  2. Each process closes its sockets:
     - `udp_server_process`: Close UDP socket, save port binding
     - `dtls_server_process`: Terminate DTLS sessions, close socket
     - `zip_tcp_client_process`: Close portal connection
     - `mDNS_server_process`: Leave multicast groups, close socket
  3. After resume: Post `PROCESS_RESUME` event
  4. Each process reopens sockets and re-establishes connections
  5. mDNS re-announces services
  6. DTLS clients must re-handshake
- **Pros:** Clean network state, no stale connections
- **Cons:** Service interruption, DTLS clients must reconnect
- **Risk Mitigation:** IP address change requires full re-initialization

**Solution 2: Network State Validation**
- **Approach:** Keep sockets open, validate network state on resume
- **Implementation Steps:**
  1. After resume: Check network interface status with `getifaddrs()`
  2. Verify IPv4 address unchanged (compare with saved address)
  3. Verify IPv6 address unchanged (link-local and global)
  4. Send mDNS probe to detect IP conflicts
  5. If network state changed:
     - Close all sockets
     - Restart network stack
     - Re-acquire DHCP lease
     - Re-bind sockets
  6. If network state unchanged:
     - Flush socket RX buffers
     - Resume normal operation
- **Pros:** Fast recovery if network unchanged, automatic fallback
- **Cons:** Complex validation logic, may miss edge cases
- **Risk Mitigation:** Periodic network health checks after resume

**Solution 3: Suspend Inhibition on Network Activity**
- **Approach:** Prevent suspend when network is actively processing packets
- **Implementation Steps:**
  1. Monitor packet queue depth (see `node_queue_state` in ZIP_Router.c)
  2. If queue is not empty or packets in-flight, acquire suspend inhibitor lock
  3. Allow suspend only when:
     - Node queue is empty (`QS_IDLE` state)
     - No active DTLS handshakes
     - No pending UDP transmissions
  4. Release inhibitor lock after 30 seconds of inactivity
- **Pros:** Prevents mid-packet suspend, data integrity guaranteed
- **Cons:** May delay suspend indefinitely on busy network
- **Risk Mitigation:** Force-allow suspend after maximum delay (e.g., 2 minutes)

---

### Issue 4: Process State Corruption

**Description:**
Z/IP Gateway uses Contiki's cooperative multitasking with protothreads. Each process maintains state in local variables and switch-case state machines. Suspend interrupts processes mid-execution, leaving them in undefined states.

**Technical Details:**
- 8+ active Contiki processes running concurrently
- Protothreads use `PROCESS_WAIT_EVENT()` which yields via `switch/case`
- Process event queue holds up to 32 events (`PROCESS_CONF_NUMEVENTS`)
- Network Management FSM has 30+ states (see `CC_NetworkManagement.h:47-295`)

**Impact Severity:** **HIGH**

**Failure Scenarios:**
1. Network Management stuck in `NM_WAITING_FOR_MDNS` state
2. Node probing halted mid-interview (incomplete capability discovery)
3. Bridge initialization suspended during virtual node creation
4. Event queue contains stale events referencing freed memory
5. Process waiting for event that will never arrive (deadlock)

**Risk Assessment:**
- **Probability:** 70% - High likelihood if suspend occurs during active NM operation
- **Impact:** Gateway stuck in non-idle state, requires restart
- **Detection Time:** Delayed (timeout or user reports malfunction)
- **Recovery:** Manual gateway restart required

**Proposed Solutions:**

**Solution 1: Process State Checkpointing**
- **Approach:** Save process states before suspend, restore on resume
- **Implementation Steps:**
  1. Add suspend/resume handlers to each Contiki process
  2. Before suspend: Each process saves critical state variables:
     - Network Management: `nms.state`, `nms.buf`, `nms.tmp_node`
     - Resource Directory: `current_probe_entry`, `probe_state`
     - Queue: `queue_state`, pending packets
  3. Clear event queue (discard stale events)
  4. After resume: Each process restores state and resumes operation
  5. For long-running operations (S2 inclusion), restart from checkpoint
- **Pros:** Preserves in-progress operations, minimal user impact
- **Cons:** Complex state serialization, error-prone
- **Risk Mitigation:** Timeout and retry logic for failed operations

**Solution 2: Suspend Rejection During Critical Operations**
- **Approach:** Only allow suspend when gateway is in idle state
- **Implementation Steps:**
  1. Monitor `zgw_state` variable (see ZIP_Router.c:168)
  2. Allow suspend only when `zgw_state == 0` (no active components)
  3. Reject suspend if any of these flags set:
     - `ZGW_BRIDGE` - Bridge operation in progress
     - `ZGW_NM` - Network Management active
     - `ZGW_BU` - Backup running
     - `ZGW_ROUTER_RESET` - Gateway resetting
  4. Check Network Management: `NetworkManagement_idle() == TRUE`
  5. Check node queue: `queue_state == QS_IDLE`
  6. Acquire systemd inhibitor lock during busy periods
- **Pros:** Guarantees clean state, prevents corruption
- **Cons:** May block suspend for extended periods (user frustration)
- **Risk Mitigation:** Force-allow after timeout (e.g., 10 minutes)

**Solution 3: State Machine Reset on Resume**
- **Approach:** Reset all state machines to idle on resume
- **Implementation Steps:**
  1. After resume: Call `process_post(PROCESS_RESUME, NULL)` to all processes
  2. Each process resets to idle state:
     - Network Management: Force state to `NM_IDLE`
     - Resource Directory: Cancel active probing, save progress
     - Queue: Flush pending packets or retry from beginning
     - Bridge: Reset to initialization start
  3. Restart gateway initialization sequence from `ZIP_Router_Reset()`
  4. Preserve database state (SQLite), discard in-memory state
- **Pros:** Simple, reliable, well-defined behavior
- **Cons:** Loss of in-progress operations (e.g., node inclusion interrupted)
- **Risk Mitigation:** Notify user via log that operation was cancelled due to suspend

---

### Issue 5: Active Transaction Interruption

**Description:**
Suspending during active Z-Wave transactions (command exchanges requiring ACK, S2 key exchange, firmware transfers) will cause incomplete operations and potential data corruption.

**Technical Details:**
- S2 inclusion requires multi-step ECDH key exchange (240 second timeout)
- Firmware update sends large payloads fragmented across multiple frames
- Network Management operations have complex callback chains
- Multi-hop routing requires ACK at each hop

**Impact Severity:** **CRITICAL**

**Failure Scenarios:**
1. S2 inclusion fails mid-ECDH exchange, node left in insecure state
2. Firmware update corruption (partial transfer, brick device)
3. Node removal incomplete, orphaned node in routing table
4. Routing assignment incomplete, node unreachable
5. Security key negotiation fails, permanent security downgrade

**Risk Assessment:**
- **Probability:** 60% - Depends on suspend timing and network activity
- **Impact:** Potential security vulnerability, device malfunction, data loss
- **Detection Time:** Immediate (operation timeout) or delayed (security issue)
- **Recovery:** Manual intervention required (re-inclusion, factory reset)

**Proposed Solutions:**

**Solution 1: Critical Operation Tracking**
- **Approach:** Maintain list of critical operations and block suspend during them
- **Implementation Steps:**
  1. Create `critical_operation_active` flag
  2. Set flag during:
     - S2 inclusion state `NM_WAITING_FOR_KEY_REPORT` to `NM_WAIT_FOR_SECURE_LEARN`
     - Firmware update `FIRMWARE_UPDATE_MD_REQUEST_GET` to completion
     - Node removal `NM_REMOVING_ASSOCIATIONS` to `NM_IDLE`
     - Backup/restore entire operation
  3. Acquire systemd inhibitor lock when flag is set
  4. Release lock when operation completes or times out
  5. Maximum inhibit duration: 5 minutes (S2 timeout is 4 minutes)
- **Pros:** Prevents data corruption, maintains security
- **Cons:** May prevent suspend during long operations
- **Risk Mitigation:** Allow force-suspend with user confirmation, abort operation safely

**Solution 2: Transaction Checkpoint and Resume**
- **Approach:** Save transaction state and resume after OS resume
- **Implementation Steps:**
  1. For S2 inclusion:
     - Save ECDH ephemeral keys and partial exchange state
     - Save DSK and granted keys
     - Resume handshake from last completed step
  2. For firmware update:
     - Save firmware fragment number and checksum
     - Resume transfer from last acknowledged fragment
  3. For Network Management:
     - Save operation type, target node, and callback context
     - Resume operation with timeout extension
- **Pros:** User experience preserved, no operation loss
- **Cons:** Extremely complex, security risks (key material in memory)
- **Risk Mitigation:** Encrypt checkpointed state, clear sensitive data on timeout

**Solution 3: Graceful Transaction Abort**
- **Approach:** Abort active transactions before suspend, notify user to retry
- **Implementation Steps:**
  1. Before suspend: Check for active critical operations
  2. Send appropriate abort frames:
     - S2 inclusion: Send `LEARN_MODE_SET_STOP`
     - Firmware update: Send `FIRMWARE_UPDATE_MD_STATUS_REPORT` with abort
     - Network Management: Call `ResetState()` to return to `NM_IDLE`
  3. Log aborted operations to syslog
  4. Update operation status in database (mark as "aborted due to suspend")
  5. After resume: Present notification to user (if GUI available)
- **Pros:** Clean state, no corruption, well-defined behavior
- **Cons:** User must retry operation manually
- **Risk Mitigation:** Auto-retry for non-security-critical operations

---

### Issue 6: Security Session Invalidation

**Description:**
DTLS sessions for secure Z/IP communication maintain session state including cipher suites, keys, and replay protection. Suspend may cause session timeout or state desynchronization.

**Technical Details:**
- DTLS implementation in `libzwaveip/libzwaveip/dtls_server.c`
- Session cache timeout typically 60-120 seconds
- S2 SPAN tables track nonce values to prevent replay attacks (SQLite storage)
- Active DTLS handshakes in progress during suspend

**Impact Severity:** **MEDIUM**

**Failure Scenarios:**
1. DTLS session expires during suspend, client cannot decrypt
2. S2 SPAN nonce desynchronization causes replay detection false positive
3. Active DTLS handshake timeout, client stuck in retry loop
4. Certificate validation fails if system time jumps on resume

**Risk Assessment:**
- **Probability:** 50% - Depends on suspend duration and session timeout
- **Impact:** Secure clients disconnected, must re-handshake
- **Detection Time:** Next DTLS packet receive/send
- **Recovery:** Automatic (clients re-handshake), transparent to user

**Proposed Solutions:**

**Solution 1: DTLS Session Termination**
- **Approach:** Close all DTLS sessions before suspend
- **Implementation Steps:**
  1. Before suspend: Enumerate active DTLS sessions
  2. Send `close_notify` alert to each client
  3. Clear session cache
  4. Flush S2 SPAN tables from memory to SQLite
  5. After resume: Wait for clients to reconnect
  6. Clients detect connection loss and re-handshake automatically
- **Pros:** Clean state, no stale sessions
- **Cons:** Brief disconnection, clients must reconnect
- **Risk Mitigation:** Standard DTLS behavior, clients expect occasional disconnects

**Solution 2: SPAN Table Persistence**
- **Approach:** Ensure SPAN tables are written to disk before suspend
- **Implementation Steps:**
  1. Before suspend: Call `S2_sync_span_table()` to flush to SQLite
  2. Ensure database transaction committed with `sqlite3_exec("COMMIT")`
  3. After resume: Reload SPAN tables from database
  4. Continue DTLS sessions if still valid (within timeout)
- **Pros:** Maintains replay protection, fast recovery
- **Cons:** DTLS sessions may still timeout on long suspend
- **Risk Mitigation:** Combine with Solution 1 for predictable behavior

**Solution 3: Session Timeout Extension**
- **Approach:** Extend DTLS session timeout to account for suspend
- **Implementation Steps:**
  1. Detect suspend duration: `suspend_duration = resume_time - suspend_time`
  2. Extend DTLS session expiry: `session->expires += suspend_duration`
  3. Adjust all timeout-based session validations
  4. For SPAN tables, no adjustment needed (monotonic sequence numbers)
- **Pros:** Maintains active sessions, no disconnection
- **Cons:** May keep sessions alive longer than intended
- **Risk Mitigation:** Set maximum session lifetime regardless of suspend

---

### Issue 7: SQLite Database Lock Issues

**Description:**
Z/IP Gateway uses SQLite for persistent storage. If suspend occurs during a database write transaction, the database may be left in a locked or inconsistent state.

**Technical Details:**
- Database file: `zipgateway.db` (location configurable)
- WAL mode (Write-Ahead Logging) enabled for concurrent access
- Active transactions during node probing, S2 operations, mailbox writes

**Impact Severity:** **MEDIUM**

**Failure Scenarios:**
1. Suspend during `BEGIN TRANSACTION`, database left locked
2. WAL file not checkpointed, accumulates unbounded size
3. Database corruption if OS crashes during suspend
4. File descriptor to database becomes invalid

**Risk Assessment:**
- **Probability:** 30% - SQLite is robust, but unclosed transactions are risky
- **Impact:** Database locked, gateway cannot start, or data loss
- **Detection Time:** Next database operation
- **Recovery:** Rollback transaction, repair database with `PRAGMA integrity_check`

**Proposed Solutions:**

**Solution 1: Transaction Commit Before Suspend**
- **Approach:** Commit all open transactions before suspend
- **Implementation Steps:**
  1. Before suspend: Call `data_store_suspend()` (new function)
  2. Commit any open transactions: `sqlite3_exec("COMMIT")`
  3. Checkpoint WAL: `sqlite3_wal_checkpoint_v2(SQLITE_CHECKPOINT_FULL)`
  4. After resume: Call `data_store_resume()` (new function)
  5. Verify database integrity: `sqlite3_exec("PRAGMA integrity_check")`
- **Pros:** Ensures data consistency, clean database state
- **Cons:** Brief delay before suspend (WAL checkpoint can be slow)
- **Risk Mitigation:** Set maximum checkpoint duration (e.g., 5 seconds)

**Solution 2: Database Connection Close/Reopen**
- **Approach:** Close database before suspend, reopen on resume
- **Implementation Steps:**
  1. Before suspend: Commit transactions, close database: `sqlite3_close()`
  2. After resume: Reopen database: `data_store_init()` (already exists)
  3. Verify database not corrupted with integrity check
  4. If corrupted, restore from backup (if available)
- **Pros:** Cleanest state, no file descriptor issues
- **Cons:** Slow resume (database reopen and schema validation)
- **Risk Mitigation:** Keep database connection open, only commit transactions

**Solution 3: WAL Journaling with Sync**
- **Approach:** Rely on SQLite's WAL mode for crash recovery
- **Implementation Steps:**
  1. Ensure WAL mode enabled: `PRAGMA journal_mode=WAL`
  2. Set aggressive sync: `PRAGMA synchronous=FULL`
  3. No special suspend handling, rely on SQLite recovery
  4. After resume: SQLite automatically recovers from WAL
- **Pros:** Minimal code changes, leverages SQLite robustness
- **Cons:** Performance overhead (FULL sync on every write)
- **Risk Mitigation:** Performance acceptable for gateway workload

---

### Issue 8: Event Queue Corruption

**Description:**
Contiki's event queue holds pending events for process dispatch. Events may reference memory that becomes invalid during suspend (e.g., stack pointers, freed buffers).

**Technical Details:**
- Event queue in `contiki/core/sys/process.c`
- Maximum 32 events (`PROCESS_CONF_NUMEVENTS`)
- Events carry `data` pointer which may be transient

**Impact Severity:** **LOW**

**Failure Scenarios:**
1. Event data pointer references freed memory
2. Event references process that was terminated
3. Stale timer events fire with incorrect context

**Risk Assessment:**
- **Probability:** 20% - Events are typically short-lived
- **Impact:** Potential crash or incorrect behavior
- **Detection Time:** When event is processed
- **Recovery:** Crash with core dump, restart required

**Proposed Solutions:**

**Solution 1: Event Queue Flush**
- **Approach:** Clear event queue before suspend
- **Implementation Steps:**
  1. Before suspend: Call `process_flush_events()` (new function)
  2. Discard all pending events
  3. After resume: Processes re-post necessary events
- **Pros:** Simple, eliminates stale event risk
- **Cons:** Loss of pending events (may impact responsiveness)
- **Risk Mitigation:** Most events are quickly regenerated

**Solution 2: Event Data Validation**
- **Approach:** Add validation to event processing
- **Implementation Steps:**
  1. Mark events with generation counter
  2. Increment counter on suspend
  3. Validate event generation before processing
  4. Discard events from previous generation
- **Pros:** Selective discard, preserves valid events
- **Cons:** Requires event structure modification
- **Risk Mitigation:** Fallback to Solution 1 if validation too complex

**Solution 3: No Action (Acceptable Risk)**
- **Approach:** Accept low probability of corruption
- **Implementation Steps:**
  1. Document known issue
  2. Add watchdog timer to detect hung processes
  3. Automatic restart on watchdog timeout
- **Pros:** No code changes, minimal overhead
- **Cons:** Occasional crashes possible
- **Risk Mitigation:** Systemd auto-restart on crash

---

## Impact on Controller Module

### Issue 9: Serial Protocol Desynchronization

**Description:**
The Z-Wave controller module continues operating during OS suspend, sending frames over the serial port that are not acknowledged. This causes the serial protocol to desynchronize.

**Technical Details:**
- Controller expects ACK within 150ms of frame transmission
- If no ACK received, controller retransmits (typically 3 attempts)
- After retransmission failure, controller may abort operation
- Controller TX buffer limited (typically 8 frames), may overflow

**Impact Severity:** **CRITICAL**

**Failure Scenarios:**
1. Controller sends unsolicited application command, receives no ACK
2. Controller retransmits frame 3 times, eventually aborts
3. Controller callback buffer overflows (lost events)
4. Protocol state desynchronization (controller expects response, gateway unaware)
5. Resume finds stale NAK or CAN frames in serial buffer

**Risk Assessment:**
- **Probability:** 100% - Will occur on every suspend if network active
- **Impact:** Lost Z-Wave events (missed commands from devices)
- **Detection Time:** Immediate (controller timeouts during suspend)
- **Recovery:** Requires serial protocol reset

**Proposed Solutions:**

**Solution 1: Serial Protocol Reset**
- **Approach:** Reset serial protocol on resume
- **Implementation Steps:**
  1. After resume: Flush serial buffers: `tcflush(serial_fd, TCIOFLUSH)`
  2. Send NAK to clear controller's pending ACK expectation
  3. Reset protocol state machine: `con_state = stateSOFHunt`
  4. Send soft reset to controller: `ZW_SoftReset()` (FUNC_ID_SERIAL_API_SOFT_RESET)
  5. Wait for controller ready (application callback or timeout)
  6. Re-verify controller state: `SerialAPI_GetInitData()`
- **Pros:** Clean resynchronization, well-defined state
- **Cons:** Lost events during suspend (permanent)
- **Risk Mitigation:** Document that suspend causes event loss

**Solution 2: Controller Event Buffer Polling**
- **Approach:** Poll controller for missed events on resume
- **Implementation Steps:**
  1. After resume and serial reset
  2. Check if controller supports event buffering (FUNC_ID_SERIAL_API_GET_INIT_DATA)
  3. Request pending application commands (controller-specific)
  4. For 700/800 series: Query NVM for missed callbacks
  5. Replay missed events through application handler
- **Pros:** Recovers missed events, no data loss
- **Cons:** Controller may not buffer events, complex implementation
- **Risk Mitigation:** Only works on newer controller generations

**Solution 3: Suspend Notification to Controller**
- **Approach:** Notify controller before suspend
- **Implementation Steps:**
  1. Before suspend: Send custom command to controller (if supported)
  2. Controller enters low-power mode, stops generating events
  3. Controller buffers incoming Z-Wave frames in NVM
  4. After resume: Send wake command
  5. Controller replays buffered events
- **Pros:** No event loss, coordinated suspend
- **Cons:** Requires controller firmware support, not available on all chips
- **Risk Mitigation:** Fallback to Solution 1 if not supported

---

### Issue 10: Watchdog Timeout (Gecko 700/800 Series)

**Description:**
Gecko-based Z-Wave controllers (700/800 series) include a watchdog timer that must be periodically reset by the host. If the host suspends, the watchdog is not kicked and the controller resets.

**Technical Details:**
- Watchdog implemented in `src/serialapi/Serialapi.c:2464-2488`
- Kick interval: Typically 1-5 seconds (controller-specific)
- Timeout: Typically 10-30 seconds
- Reset causes controller to reload from NVM, brief network unavailability

**Impact Severity:** **HIGH**

**Failure Scenarios:**
1. OS suspends for > watchdog timeout (e.g., 30 seconds)
2. Watchdog expires, controller performs hardware reset
3. Controller reloads NVM, re-initializes Z-Wave radio
4. HomeID and NodeID preserved, but runtime state lost
5. Active network management operations aborted
6. Routing table cache cleared, network performance degraded until rebuilt

**Risk Assessment:**
- **Probability:** 80% - Likely on suspends longer than 30 seconds
- **Impact:** Controller reset, temporary network disruption (5-30 seconds)
- **Detection Time:** On resume when gateway queries controller
- **Recovery:** Automatic (controller reinitializes), but operation loss

**Proposed Solutions:**

**Solution 1: Pre-Suspend Watchdog Disable**
- **Approach:** Disable watchdog before suspend
- **Implementation Steps:**
  1. Before suspend: Send `FUNC_ID_SERIALAPI_SETUP` with watchdog disable
  2. Wait for ACK from controller
  3. After resume: Send `FUNC_ID_SERIALAPI_SETUP` with watchdog enable
  4. Resume normal watchdog kicking
- **Pros:** Prevents controller reset, maintains state
- **Cons:** Requires controller firmware support (700 series v7.11+)
- **Risk Mitigation:** Check controller capabilities before using

**Solution 2: Controller Reset Detection and Recovery**
- **Approach:** Accept controller reset, detect and recover
- **Implementation Steps:**
  1. After resume: Query controller HomeID and NodeID
  2. Compare with saved values
  3. If different (controller reset detected):
     - Re-initialize serial API: `SerialAPI_Init()`
     - Verify network parameters unchanged
     - Restart gateway processes
  4. If same:
     - Assume controller state preserved
     - Resume normal operation
- **Pros:** Robust, works on all controller types
- **Cons:** Brief network disruption, lost in-flight operations
- **Risk Mitigation:** Standard recovery path, well-tested

**Solution 3: Suspend Duration Limitation**
- **Approach:** Prevent long suspends when gateway is active
- **Implementation Steps:**
  1. Determine controller watchdog timeout (query capabilities)
  2. Acquire systemd inhibitor lock with `--why="Z-Wave controller requires periodic communication"`
  3. Allow suspend only if controller supports watchdog disable
  4. Otherwise, prevent suspend entirely (display warning)
- **Pros:** Guarantees no controller reset
- **Cons:** May prevent system suspend entirely
- **Risk Mitigation:** User education, configuration option to override

---

### Issue 11: Controller Buffer Overflow

**Description:**
During OS suspend, Z-Wave devices continue communicating with the controller. The controller's internal RX buffer may overflow if too many messages arrive without being read by the host.

**Technical Details:**
- Controller RX buffer size: Typically 256-512 bytes (controller-specific)
- Average Z-Wave frame size: 30-60 bytes
- Buffer capacity: ~8-16 frames
- Overflow behavior: Oldest frames dropped (FIFO)

**Impact Severity:** **MEDIUM**

**Failure Scenarios:**
1. During 10-minute suspend, 20 Z-Wave events occur
2. Controller buffer holds only 10 events
3. Oldest 10 events dropped permanently
4. On resume, gateway only sees latest 10 events
5. Missed events may include:
   - Security alarms (door sensor, motion detector)
   - Actuator state changes (light turned on/off)
   - Meter readings (energy consumption)

**Risk Assessment:**
- **Probability:** 40% - Depends on network activity and suspend duration
- **Impact:** Missed events, incorrect device state, security concerns
- **Detection Time:** Never (dropped events are invisible)
- **Recovery:** Requires manual state synchronization or device polling

**Proposed Solutions:**

**Solution 1: Post-Resume Device Polling**
- **Approach:** Poll all devices after resume to sync state
- **Implementation Steps:**
  1. After resume: Mark all devices as "state unknown"
  2. For each device in Resource Directory:
     - Send `BASIC_GET` or `MULTILEVEL_SENSOR_GET`
     - Update cached state in database
  3. Throttle polling to avoid network congestion (1 device/second)
  4. Prioritize critical devices (sensors, locks)
- **Pros:** Ensures state accuracy, simple implementation
- **Cons:** Network congestion, battery drain on sleeping devices
- **Risk Mitigation:** Only poll mains-powered frequently listening devices

**Solution 2: Event Loss Detection**
- **Approach:** Detect buffer overflow via controller status
- **Implementation Steps:**
  1. After resume: Query controller status (if supported)
  2. Check for overflow flag or sequence number gap
  3. If overflow detected:
     - Log warning with count of lost events
     - Trigger device polling (Solution 1)
  4. If no overflow:
     - Resume normal operation
- **Pros:** Efficient, only polls when necessary
- **Cons:** Requires controller support for overflow detection
- **Risk Mitigation:** Assume overflow on long suspends (>5 minutes)

**Solution 3: Suspend Duration Limitation**
- **Approach:** Prevent suspends longer than buffer capacity
- **Implementation Steps:**
  1. Estimate buffer capacity from controller capabilities
  2. Calculate maximum safe suspend duration:
     - Assume worst-case: 1 event per second
     - Buffer capacity: 10 events
     - Maximum suspend: 10 seconds
  3. Acquire systemd inhibitor with timeout (10 seconds)
  4. Force resume or allow suspend after timeout
- **Pros:** Prevents buffer overflow
- **Cons:** Very short suspend limit, impractical for user
- **Risk Mitigation:** Combine with Solution 1 for long suspends

---

### Issue 12: Network State Desynchronization

**Description:**
While the OS is suspended, the Z-Wave network continues operating. Devices may join/leave the network, routing table updates may occur, and network topology may change. The gateway's cached state becomes stale.

**Technical Details:**
- Controller maintains authoritative network topology in NVM
- Gateway caches device list, routing tables, and neighbor information
- Network topology changes during suspend are only known to controller

**Impact Severity:** **HIGH**

**Failure Scenarios:**
1. User adds device via alternate controller during suspend
2. Gateway's resource directory doesn't know about new device
3. Device unreachable until gateway rediscovers it
4. Routing table out of sync, inefficient routes used
5. Security keys negotiated with other controller, gateway unaware

**Risk Assessment:**
- **Probability:** 10% - Rare, requires manual intervention during suspend
- **Impact:** Device unavailable, manual rediscovery required
- **Detection Time:** User reports device missing
- **Recovery:** Manual network rediscovery or automatic on next probe cycle

**Proposed Solutions:**

**Solution 1: Full Network Rediscovery**
- **Approach:** Rediscover all devices after resume
- **Implementation Steps:**
  1. After resume: Query controller's current node list
  2. Compare with gateway's cached node list from resource directory
  3. For new nodes:
     - Add to resource directory
     - Initiate node interview (probe)
  4. For removed nodes:
     - Mark as failed in resource directory
     - Update IP associations
  5. Request routing table update for all nodes
- **Pros:** Ensures perfect synchronization
- **Cons:** Slow (5-30 minutes for large networks), network congestion
- **Risk Mitigation:** Only rediscover if controller node list changed

**Solution 2: Incremental Node List Sync**
- **Approach:** Quick node list comparison, minimal probing
- **Implementation Steps:**
  1. After resume: Call `ZW_GetNodeList()` from controller
  2. Compare with cached list in database
  3. If identical:
     - Assume no changes, resume normal operation
  4. If different:
     - Log warning
     - Re-probe only changed nodes
     - Update resource directory incrementally
- **Pros:** Fast (1-5 seconds), minimal network impact
- **Cons:** Doesn't detect routing changes, only node add/remove
- **Risk Mitigation:** Periodic full rediscovery (e.g., daily)

**Solution 3: Controller Change Notification**
- **Approach:** Controller notifies gateway of topology changes
- **Implementation Steps:**
  1. Before suspend: Register for controller change notifications (if supported)
  2. After resume: Check for pending change notifications
  3. If changes detected:
     - Process each change event (node added, removed, updated)
     - Update resource directory accordingly
  4. If no changes:
     - Resume normal operation
- **Pros:** Efficient, accurate, minimal overhead
- **Cons:** Requires controller firmware support (not universally available)
- **Risk Mitigation:** Fallback to Solution 2 if not supported

---

### Issue 13: Routing Table Staleness

**Description:**
Z-Wave uses dynamic routing with neighbor tables and last-working routes. During suspend, the controller may update routing information based on frame delivery success/failure. The gateway's view of routing becomes stale.

**Technical Details:**
- Controller maintains routing cache in RAM (last working route, speed)
- Neighbor tables updated based on periodic neighbor discovery
- Return routes assigned for battery devices may change

**Impact Severity:** **LOW**

**Failure Scenarios:**
1. During suspend, direct route to device fails
2. Controller discovers new multi-hop route
3. Gateway unaware of route change
4. Gateway continues using stale route information for diagnostics
5. Network performance suboptimal until next route update

**Risk Assessment:**
- **Probability:** 30% - Possible on long suspends with network activity
- **Impact:** Suboptimal routing, minor performance degradation
- **Detection Time:** Never (invisible to user, automatic adaptation)
- **Recovery:** Automatic (controller adapts routes transparently)

**Proposed Solutions:**

**Solution 1: Routing Table Invalidation**
- **Approach:** Mark routing cache as stale after resume
- **Implementation Steps:**
  1. After resume: Invalidate gateway's routing cache
  2. Set flag: `routing_table_valid = false`
  3. On next routing query, request fresh data from controller
  4. Controller provides current routing information
  5. Update gateway cache
- **Pros:** Simple, ensures fresh data
- **Cons:** Minor delay on first routing query after resume
- **Risk Mitigation:** Pre-fetch routing table during resume process

**Solution 2: Routing Table Refresh**
- **Approach:** Proactively refresh routing table on resume
- **Implementation Steps:**
  1. After resume: For each node in network:
     - Query `ZW_GetRoutingInfo()` from controller
     - Update gateway's routing cache
  2. For large networks (>50 nodes), throttle requests
  3. Prioritize frequently-used devices
- **Pros:** Proactive, ensures accuracy
- **Cons:** Slow on large networks (serial API overhead)
- **Risk Mitigation:** Background refresh, don't block gateway startup

**Solution 3: No Action (Acceptable)**
- **Approach:** Accept that routing table may be stale
- **Implementation Steps:**
  1. Document that routing information is best-effort
  2. Routing is primarily controller responsibility
  3. Gateway uses routing info for diagnostics only
  4. Controller always has authoritative routing data
- **Pros:** No code changes, minimal impact
- **Cons:** Diagnostic information may be incorrect
- **Risk Mitigation:** Clearly document in logs that routing info is cached

---

## Risk Summary Matrix

| Issue | Component | Severity | Probability | Impact | Recommended Solution |
|-------|-----------|----------|-------------|--------|---------------------|
| 1. Serial Port Disruption | Host | CRITICAL | 95% | Complete communication loss | Solution 1: Disconnect/Reconnect |
| 2. Timer Desynchronization | Host | CRITICAL | 100% | Timed operations fail | Solution 3: CLOCK_BOOTTIME |
| 3. Network Socket Disruption | Host | HIGH | 80% | LAN connectivity loss | Solution 2: State Validation |
| 4. Process State Corruption | Host | HIGH | 70% | Gateway stuck, restart needed | Solution 2: Suspend Rejection |
| 5. Transaction Interruption | Host | CRITICAL | 60% | Data corruption, security risk | Solution 1: Critical Op Tracking |
| 6. Security Session Invalid | Host | MEDIUM | 50% | DTLS reconnect required | Solution 1: Session Termination |
| 7. Database Lock | Host | MEDIUM | 30% | Database locked/corrupt | Solution 1: Commit Before Suspend |
| 8. Event Queue Corruption | Host | LOW | 20% | Potential crash | Solution 1: Queue Flush |
| 9. Serial Protocol Desync | Controller | CRITICAL | 100% | Lost Z-Wave events | Solution 1: Protocol Reset |
| 10. Watchdog Timeout | Controller | HIGH | 80% | Controller reset | Solution 1: Watchdog Disable |
| 11. Buffer Overflow | Controller | MEDIUM | 40% | Missed events | Solution 1: Post-Resume Polling |
| 12. Network State Desync | Controller | HIGH | 10% | Missing devices | Solution 2: Node List Sync |
| 13. Routing Table Stale | Controller | LOW | 30% | Suboptimal routing | Solution 3: No Action |

---

## Implementation Roadmap

### Phase 1: Critical Fixes (Prevent Data Corruption)
**Priority:** HIGH - Must implement before suspend support

1. **Serial Port Management**
   - Implement graceful serial disconnect/reconnect
   - Add suspend/resume handlers
   - Test: 100 suspend/resume cycles, verify communication restored

2. **Timer Fix**
   - Switch to `CLOCK_BOOTTIME` in `clock.c`
   - Test: Verify timers with suspend durations of 1s, 1m, 1h, 10h

3. **Critical Operation Tracking**
   - Add systemd inhibitor lock infrastructure
   - Block suspend during S2 inclusion, firmware update, backup
   - Test: Attempt suspend during each critical operation

4. **Serial Protocol Reset**
   - Implement post-resume serial protocol reset
   - Add controller state verification
   - Test: Verify communication restored, measure event loss

### Phase 2: State Management (Improve Reliability)
**Priority:** MEDIUM - Enhance user experience

1. **Network Socket Validation**
   - Implement network state check on resume
   - Add socket reconnect logic
   - Test: Resume with/without IP address change

2. **Database Transaction Management**
   - Add pre-suspend commit
   - Add WAL checkpoint
   - Test: Suspend during database write, verify no corruption

3. **Process Suspend/Resume Handlers**
   - Add `PROCESS_SUSPEND` and `PROCESS_RESUME` events
   - Implement handlers in critical processes
   - Test: Verify processes resume correctly

4. **Watchdog Management**
   - Detect controller capabilities (watchdog disable support)
   - Implement watchdog disable/enable on suspend/resume
   - Fallback: Detect and recover from controller reset
   - Test: Both paths (with and without watchdog disable)

### Phase 3: Advanced Features (Minimize Event Loss)
**Priority:** LOW - Nice to have

1. **Post-Resume Device Polling**
   - Implement selective device polling after resume
   - Prioritize critical devices (sensors, locks)
   - Test: Measure time to full state sync

2. **Network Topology Sync**
   - Implement node list comparison
   - Add incremental probe for changed nodes
   - Test: Add device during suspend, verify detection

3. **DTLS Session Management**
   - Implement graceful DTLS session termination
   - Add SPAN table flush
   - Test: DTLS client resume and re-handshake

4. **Logging and Diagnostics**
   - Add suspend/resume event logging
   - Log aborted operations
   - Measure suspend/resume duration
   - Test: Verify logs useful for troubleshooting

---

## Testing Strategy

### Unit Tests
1. **Serial Port Test**
   - Open, suspend, resume, verify communication
   - Test with stale data in buffers
   - Test with device reassignment (/dev/ttyUSB0 → /dev/ttyUSB1)

2. **Timer Test**
   - Set timer for 10 seconds, suspend for 30 seconds, verify timer fires correctly
   - Test short suspend (< timer duration)
   - Test long suspend (> timer duration)

3. **Database Test**
   - Start transaction, suspend, resume, verify commit/rollback
   - Test WAL checkpoint
   - Test database integrity after 100 suspend/resume cycles

### Integration Tests
1. **Node Inclusion During Suspend**
   - Start S2 inclusion
   - Suspend at each state in NM FSM
   - Verify graceful abort or completion

2. **Active Network During Suspend**
   - Generate continuous Z-Wave traffic (sensor reports every 1s)
   - Suspend for various durations (10s, 1m, 10m)
   - Measure event loss rate
   - Verify network recovers

3. **Multi-Hour Suspend**
   - Suspend overnight (8 hours)
   - Verify full functionality on resume
   - Check for memory leaks, resource exhaustion

### Stress Tests
1. **Rapid Suspend/Resume**
   - 1000 suspend/resume cycles with 1-second intervals
   - Verify no crashes, no resource leaks
   - Measure resume time trend (ensure no degradation)

2. **Suspend Under Load**
   - Heavy network traffic (100 packets/second)
   - Frequent database writes
   - Suspend and verify recovery

### Real-World Scenarios
1. **Laptop Lid Close**
   - Close laptop lid, wait 1 hour, open
   - Verify network connectivity restored
   - Verify Z-Wave devices responsive

2. **Idle Suspend**
   - Configure systemd to suspend after 5 minutes idle
   - Leave gateway idle, verify automatic suspend
   - Verify automatic resume on network activity (WoL)

---

## Configuration Options

Add configuration to `/usr/local/etc/zipgateway.cfg`:

```ini
[suspend]
# Enable suspend/resume support (default: true)
# Set to false to prevent OS suspend entirely
enable_suspend=true

# Allow suspend during non-critical operations (default: true)
# Set to false to only allow suspend when gateway is completely idle
allow_suspend_when_busy=true

# Maximum suspend duration in seconds (default: 3600 = 1 hour)
# Longer suspends may cause event loss
max_suspend_duration=3600

# Post-resume device polling (default: critical)
# Options: none, critical (sensors/locks only), all
post_resume_polling=critical

# Abort active operations on suspend (default: true)
# Set to false to prevent suspend during critical operations
abort_operations_on_suspend=true

# Log suspend/resume events (default: true)
log_suspend_events=true
```

---

## D-Bus Integration (Linux)

Use systemd logind D-Bus interface to detect suspend/resume:

```c
// Subscribe to PrepareForSleep signal
dbus_bus_add_match(connection,
    "type='signal',"
    "interface='org.freedesktop.login1.Manager',"
    "member='PrepareForSleep'",
    &error);

// Signal handler
void on_prepare_for_sleep(DBusMessage *msg) {
    dbus_bool_t suspending;
    dbus_message_get_args(msg, NULL,
        DBUS_TYPE_BOOLEAN, &suspending,
        DBUS_TYPE_INVALID);

    if (suspending) {
        // About to suspend
        zgw_prepare_suspend();
    } else {
        // Just resumed
        zgw_handle_resume();
    }
}
```

---

## Monitoring and Alerts

### Syslog Messages

**Pre-Suspend:**
```
zipgateway[1234]: Preparing for system suspend
zipgateway[1234]: Aborting S2 inclusion (node 15) due to suspend
zipgateway[1234]: Closing serial port /dev/ttyUSB0
zipgateway[1234]: Committing database transactions
zipgateway[1234]: Ready for suspend
```

**Post-Resume:**
```
zipgateway[1234]: System resumed from suspend (duration: 3672 seconds)
zipgateway[1234]: Reopening serial port /dev/ttyUSB0
zipgateway[1234]: Controller state verified (HomeID: 0x12345678, NodeID: 1)
zipgateway[1234]: Network sockets restored
zipgateway[1234]: Polling 5 critical devices for state update
zipgateway[1234]: Resume complete (duration: 2.3 seconds)
```

**Errors:**
```
zipgateway[1234]: ERROR: Serial port open failed after resume: No such device
zipgateway[1234]: ERROR: Controller reset detected (HomeID changed)
zipgateway[1234]: ERROR: Database integrity check failed
zipgateway[1234]: WARNING: Lost an estimated 15 Z-Wave events during suspend
```

### Metrics

Expose suspend/resume metrics via DTLS interface or mDNS:

- `suspend_count`: Number of suspend/resume cycles
- `last_suspend_duration`: Duration of last suspend in seconds
- `resume_time`: Time to restore full functionality in seconds
- `estimated_event_loss`: Estimated number of lost Z-Wave events
- `controller_reset_count`: Number of times controller reset during suspend

---

## Conclusion

Operating system suspend/resume poses **significant challenges** to Z/IP Gateway due to its:
- Real-time serial communication requirements
- Stateful network connections
- Software-based timer infrastructure
- Complex finite state machines

However, with the implementation roadmap outlined in this document, suspend/resume support can be achieved with **acceptable trade-offs**:

**Acceptable:**
- Brief communication outage (1-2 seconds on resume)
- DTLS session reconnection required
- Possible loss of Z-Wave events during suspend
- Abort of non-critical operations

**Not Acceptable (Prevented):**
- Data corruption
- Security vulnerabilities
- Permanent loss of network state
- Controller bricking

**Recommended Minimum Implementation:**
1. Serial port disconnect/reconnect (Issue 1, 9)
2. CLOCK_BOOTTIME timer fix (Issue 2)
3. Critical operation tracking (Issue 5)
4. Watchdog management (Issue 10)

This minimum implementation addresses the most critical issues and prevents data corruption, at the cost of some event loss and service interruption during suspend.

**Estimated Effort:**
- Phase 1 (Critical Fixes): 3-4 weeks, 1 engineer
- Phase 2 (State Management): 2-3 weeks, 1 engineer
- Phase 3 (Advanced Features): 2-3 weeks, 1 engineer
- Testing: 2 weeks, 1 QA engineer
- **Total: 9-12 weeks**

---

## References

- Z/IP Gateway source code: `/home/user/zipgateway/`
- Serial API implementation: `src/serialapi/Serialapi.c`
- Contiki OS: `contiki/core/sys/process.c`
- Linux serial port: `contiki/cpu/native/linux-serial.c`
- Timer implementation: `contiki/platform/linux/clock.c`
- Network Management FSM: `src/CC_NetworkManagement.h`
- systemd inhibitor API: `man systemd-inhibit`
- D-Bus logind interface: `man org.freedesktop.login1`

---

**Document Version:** 1.0
**Date:** 2025-11-16
**Author:** Claude (AI Analysis)
**Review Status:** Draft - Requires technical review by Z-Wave protocol experts
