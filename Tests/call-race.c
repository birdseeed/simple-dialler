// Exercise the real callback and hangup functions with deterministic PJ observations.
// No engine, socket, account or audio is created by this test.
#define pjsua_call_get_info simulated_call_get_info
#define pjsua_call_hangup simulated_call_hangup
#include "../Sources/SIPBridge.c"
#include <assert.h>

static pjsua_call_info observed;
static pjsua_call_id hung_up = PJSUA_INVALID_ID;

pj_status_t simulated_call_get_info(pjsua_call_id id, pjsua_call_info *info) {
    assert(id == observed.id);
    *info = observed;
    return PJ_SUCCESS;
}

pj_status_t simulated_call_hangup(pjsua_call_id id, unsigned code,
                                const pj_str_t *reason, const pjsua_msg_data *message) {
    (void)code; (void)reason; (void)message;
    hung_up = id;
    return PJ_SUCCESS;
}

static void emit(pjsua_call_id id, pjsip_role_e role, pjsip_inv_state call_state) {
    memset(&observed, 0, sizeof(observed));
    observed.id = id;
    observed.role = role;
    observed.state = call_state;
    observed.last_status = role == PJSIP_ROLE_UAS ? 486 : 200;
    observed.remote_info = pj_str("sip:fixture@example.test");
    call_changed(id, NULL);
}

int main(void) {
    // Match the outgoing reservation published immediately before make_call.
    current = -2;
    state.call = 2;
    state.call_generation = 7;

    // A concurrent incoming call is rejected. Neither its progress nor final
    // callback may adopt or clear the reserved outgoing call.
    emit(1, PJSIP_ROLE_UAS, PJSIP_INV_STATE_EARLY);
    assert(current == -2 && state.call == 2 && state.call_generation == 7);
    emit(1, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    assert(current == -2 && state.call == 2);

    // The actual outgoing callback must claim the reservation and remain the
    // target of the public hangup API, even after another rejected callback.
    emit(0, PJSIP_ROLE_UAC, PJSIP_INV_STATE_CALLING);
    assert(current == 0 && state.call == 2);
    emit(1, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    assert(current == 0 && state.call == 2);
    emit(0, PJSIP_ROLE_UAC, PJSIP_INV_STATE_CONFIRMED);
    assert(state.call == 3);
    assert(sd_hangup() == PJ_SUCCESS && hung_up == 0);
    emit(0, PJSIP_ROLE_UAC, PJSIP_INV_STATE_DISCONNECTED);
    assert(current == PJSUA_INVALID_ID && state.call == 0);

    puts("Passed outgoing reservation race: rejected incoming callbacks cannot steal tracking; hangup targets outgoing call.");
    return 0;
}
