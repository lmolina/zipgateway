/* Copyright Silicon Laboratories Inc.
 *
 * Verify that LR node IDs (>255) are not truncated when S2_wrap.c's
 * multicast follow-up state machine forwards them to S2_send_data().
 *
 * Compiled with -DTEST_MULTICAST_TX so the follow-up code path is active.
 */

#include <string.h>
#include <stdint.h>

#include "unity.h"
#include "S2_wrap.h"        /* sec2_send_multicast, sec2_init */
#include "zgw_nodemask.h"
#include "s2_protocol.h"   /* s2_connection_t, s2_tx_status_t */
#include "S2.h"            /* S2_TRANSMIT_COMPLETE_OK */

/* ------------------------------------------------------------------ */
/* Mocks for S2_send_data_multicast and S2_send_data                  */
/* ------------------------------------------------------------------ */

static int s2_send_data_multicast_call_count;
static int s2_send_data_call_count;
static s2_connection_t captured_s2_con;

/* Called by sec2_send_multicast() – return 1 (accepted) and
 * immediately drive the state machine into the follow-up phase. */
uint8_t S2_send_data_multicast(struct S2 *ctxt,
                               const s2_connection_t *dst,
                               const uint8_t *buf, uint16_t len)
{
  (void)dst;
  (void)buf;
  (void)len;
  s2_send_data_multicast_call_count++;
  /* Fire the S2 done callback so the follow-up state machine runs. */
  S2_send_done_event(ctxt, S2_TRANSMIT_COMPLETE_OK);
  return 1;
}

/* Called for each follow-up unicast – capture the connection so we
 * can assert the node IDs are not truncated. */
uint8_t S2_send_data(struct S2 *ctxt,
                     s2_connection_t *peer,
                     const uint8_t *buf, uint16_t len)
{
  (void)ctxt;
  (void)buf;
  (void)len;
  s2_send_data_call_count++;
  captured_s2_con = *peer;
  /* Return 1 so the state machine does not abort immediately. */
  return 1;
}

/* ------------------------------------------------------------------ */
/* Stubs required to link S2_wrap.c                                   */
/* ------------------------------------------------------------------ */

/* multicast_group_manager */
#include "multicast_group_manager.h"
mcast_groupid_t mcast_group_get_id_by_nodemask(const nodemask_t nodemask)
{
  (void)nodemask;
  return 1;
}

/* ctimer / clock */
#include "ctimer.h"
#include "clock.h"
void ctimer_set(struct ctimer *c, clock_time_t t, void (*f)(void *), void *ptr)
{
  (void)c; (void)t; (void)f; (void)ptr;
}
void ctimer_stop(struct ctimer *c) { (void)c; }
clock_time_t clock_time(void) { return 0; }

/* NVM read/write (backing nvm_config_get / nvm_config_set macros) */
#include "zw_appl_nvm.h"
static uint8_t nvm_buf[4096];
int zw_appl_nvm_read(u16_t start, void *dst, u8_t size)
{
  memcpy(dst, &nvm_buf[start], size);
  return 0;
}
void zw_appl_nvm_write(u16_t start, const void *src, u8_t size)
{
  memcpy(&nvm_buf[start], src, size);
}

/* s2_inclusion stubs */
#include "s2_inclusion.h"
uint8_t s2_inclusion_init(uint8_t schemes, uint8_t curves, uint8_t keys)
{
  (void)schemes; (void)curves; (void)keys; return 0;
}
void s2_inclusion_set_event_handler(s2_event_handler_t h) { (void)h; }
void s2_inclusion_key_grant(struct S2 *p, uint8_t include, uint8_t keys, uint8_t csa)
{
  (void)p; (void)include; (void)keys; (void)csa;
}
void s2_inclusion_challenge_response(struct S2 *p, uint8_t include,
                                     const uint8_t *rsp, uint8_t len)
{
  (void)p; (void)include; (void)rsp; (void)len;
}
void s2_inclusion_joining_start(struct S2 *p, s2_connection_t *conn, uint8_t csa)
{
  (void)p; (void)conn; (void)csa;
}
void s2_inclusion_neighbor_discovery_complete(struct S2 *p) { (void)p; }
void s2_inclusion_including_start(struct S2 *p, s2_connection_t *peer)
{
  (void)p; (void)peer;
}
void s2_inclusion_abort(struct S2 *p) { (void)p; }
void s2_inclusion_notify_timeout(struct S2 *p) { (void)p; }
uint8_t s2_get_key_count(void) { return 4; }

/* print_hex – extern declared in S2_wrap.c */
void print_hex(uint8_t *buf, int len) { (void)buf; (void)len; }

/* send_data – extern declared in S2_wrap.c */
#include "ZW_SendDataAppl.h"
u8_t send_data(ts_param_t *p, const u8_t *data, u16_t len,
               ZW_SendDataAppl_Callback_t cb, void *user)
{
  (void)p; (void)data; (void)len; (void)cb; (void)user; return 1;
}

/* ApplicationCommandHandlerZIP – declared in ZIP_Router.h; include it here
 * to ensure the definition matches the declaration exactly. */
#include "ZIP_Router.h"
void ApplicationCommandHandlerZIP(ts_param_t *p,
    ZW_APPLICATION_TX_BUFFER *pCmd, WORD cmdLength) CC_REENTRANT_ARG
{
  (void)p; (void)pCmd; (void)cmdLength;
}

/* CommandAnalyzerIsGet */
#include "analyzer/CommandAnalyzer.h"
int CommandAnalyzerIsGet(uint8_t cls, uint8_t cmd) { (void)cls; (void)cmd; return 0; }

/* mb_is_busy */
#include "Mailbox.h"
uint8_t mb_is_busy(void) { return 0; }

/* s2_inclusion_event_name */
#include "ZIP_Router_logging.h"
const char *s2_inclusion_event_name(int state) { (void)state; return ""; }

/* SecureClasses globals */
#include "ZW_ZIPApplication.h"
BYTE SecureClasses[40];
BYTE nSecureClasses = 0;
BYTE IPSecureClasses[40];
BYTE IPnSecureClasses = 0;
BYTE SecureClassesPAN[40];
BYTE nSecureClassesPAN = 0;

/* MyNodeID / homeID */
#include "zw_network_info.h"
nodeid_t MyNodeID = 1;
uint32_t homeID = 0xDEADBEEF;

/* global_mcast_status / global_mcast_status_len (defined in multicast_tlv.c,
 * but we don't link multicast_tlv.c in this test because it pulls heavy deps) */
#include "multicast_tlv.h"
mcast_status_t global_mcast_status[ZW_MAX_NODES];
unsigned int global_mcast_status_len;

/* ts_set_std */
void ts_set_std(ts_param_t *p, nodeid_t dnode) { (void)p; (void)dnode; }

/* memb_alloc / memb_free / memb_free_count */
#include "memb.h"
void *memb_alloc(struct memb *m) { (void)m; return NULL; }
char  memb_free(struct memb *m, void *ptr) { (void)m; (void)ptr; return 0; }
int   memb_free_count(struct memb *m) { (void)m; return 0; }

/* S2 callback stubs (called by libs2 internals — not reached in this test) */
void S2_send_frame_done_notify(struct S2 *ctxt, s2_tx_status_t status, uint16_t tx_time)
{
  (void)ctxt; (void)status; (void)tx_time;
}
void S2_timeout_notify(struct S2 *ctxt) { (void)ctxt; }
void S2_application_command_handler(struct S2 *ctxt, s2_connection_t *peer,
                                    uint8_t *buf, uint16_t len)
{
  (void)ctxt; (void)peer; (void)buf; (void)len;
}

/* dev_urandom */
#include "random.h"
int dev_urandom(int len, uint8_t *buf) { memset(buf, 0xAB, (size_t)len); return 1; }

/* send_to_both_unsoc_dest */
void send_to_both_unsoc_dest(const uint8_t *frame, uint16_t len,
                             ZW_SendDataAppl_Callback_t cbFunc)
{
  (void)frame; (void)len; (void)cbFunc;
}

/* DataStore stubs */
#include "DataStore.h"
void rd_datastore_persist_s2_span_table(const struct SPAN *span_table, size_t sz)
{
  (void)span_table; (void)sz;
}
void rd_datastore_unpersist_s2_span_table(struct SPAN *span_table, size_t sz)
{
  (void)span_table; (void)sz;
}

/* s2_keystore stubs */
#include "s2_keystore.h"
bool keystore_network_key_write(uint8_t keyclass, const uint8_t *keybuf)
{
  (void)keyclass; (void)keybuf; return true;
}

/* security_layer stubs */
#include "security_layer.h"
void sec0_abort_inclusion(void) {}

/* CC_NetworkManagement stubs */
#include "CC_NetworkManagement.h"
void NetworkManagement_dsk_challenge(s2_node_inclusion_challenge_t *ev) { (void)ev; }
void NetworkManagement_key_request(s2_node_inclusion_request_t *ev) { (void)ev; }

/* net_scheme (extern in ZW_ZIPApplication.h – already included above) */
security_scheme_t net_scheme = NO_SCHEME;

/* S2 library stubs (libs2) */
#include "S2.h"
struct S2 *S2_init_ctx(uint32_t home)
{
  (void)home; return NULL;
}
void S2_destroy(struct S2 *ctxt) { (void)ctxt; }

/* s2_ctr_drbg / AES_CTR_DRBG_Generate */
#include "ctr_drbg.h"
CTR_DRBG_CTX s2_ctr_drbg;
void AES_CTR_DRBG_Generate(CTR_DRBG_CTX *ctx, uint8_t *rand)
{
  (void)ctx; memset(rand, 0xAB, 32);
}

/* ------------------------------------------------------------------ */
/* Test callback                                                        */
/* ------------------------------------------------------------------ */

static int mc_callback_count;
static uint8_t mc_callback_status;

static void mc_callback(BYTE txStatus, void *user, TX_STATUS_TYPE *txStatEx)
{
  (void)user;
  (void)txStatEx;
  mc_callback_status = txStatus;
  mc_callback_count++;
}

/* ------------------------------------------------------------------ */
/* setUp / tearDown                                                     */
/* ------------------------------------------------------------------ */

void setUp(void)
{
  s2_send_data_multicast_call_count = 0;
  s2_send_data_call_count = 0;
  memset(&captured_s2_con, 0, sizeof(captured_s2_con));
  mc_callback_count = 0;
  mc_callback_status = 0xFF;
}

void tearDown(void) {}

/* ------------------------------------------------------------------ */
/* Test                                                                 */
/* ------------------------------------------------------------------ */

/*
 * Source is an LR node (257).  Destination is a classic node (100) so the
 * nodemask iteration loop finds it without needing to cross the 233-255 gap.
 *
 * Before the fix, mc_state.l_node is uint8_t so 257 truncates to 1.
 * After the fix (nodeid_t), 257 is preserved all the way to S2_send_data.
 */
void test_lr_source_node_id_not_truncated_in_followup(void)
{
  ts_param_t p;
  nodemask_t dest;
  const uint8_t payload[] = { 0x98, 0x01, 0xAA };

  memset(&p, 0, sizeof(p));
  nodemask_clear(dest);

  p.snode = 257;
  nodemask_add_node(100, dest);
  memcpy(p.node_list, dest, sizeof(nodemask_t));
  p.scheme = SECURITY_SCHEME_2_UNAUTHENTICATED;

  uint8_t rc = sec2_send_multicast(&p, payload, sizeof(payload),
                                   /*send_sc_followups=*/TRUE,
                                   mc_callback, NULL);
  TEST_ASSERT_EQUAL_MESSAGE(1, rc, "sec2_send_multicast should return 1");
  TEST_ASSERT_EQUAL_MESSAGE(1, s2_send_data_multicast_call_count,
                            "S2_send_data_multicast call count");
  TEST_ASSERT_EQUAL_MESSAGE(1, s2_send_data_call_count,
                            "S2_send_data call count for follow-up to node 100");

  /* l_node carries the LR source node ID through mc_state into S2_send_data.
   * With uint8_t it would be truncated to 1 (257 & 0xFF = 1). */
  TEST_ASSERT_EQUAL_UINT16_MESSAGE(257, captured_s2_con.l_node,
    "l_node must be 257, not 1 (uint8_t truncation of LR source node ID)");
  TEST_ASSERT_EQUAL_UINT16_MESSAGE(100, captured_s2_con.r_node,
    "r_node must be 100 (classic destination)");
}
