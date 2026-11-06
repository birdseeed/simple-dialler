// Exercise the real callback and hangup functions with deterministic PJ observations.
// No engine, socket, account or audio is created by this test.
#define pjsua_call_get_info simulated_call_get_info
#define pjsua_call_hangup simulated_call_hangup
#define pjsua_call_answer simulated_call_answer
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

static unsigned answered_code;
pj_status_t simulated_call_answer(pjsua_call_id call, unsigned code,
                                  const pj_str_t *reason, const pjsua_msg_data *message) {
    (void)call; (void)reason; (void)message;
    answered_code = code;
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

    // Preserve completed incoming events even when the UI never saw ringing.
    current = 0; state.call = 1; incoming_outcome = 1;
    emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    SDIncomingResult result;
    assert(sd_next_incoming(&result) && result.outcome == 1);
    assert(strcmp(result.remote, "sip:fixture@example.test") == 0);
    assert(!sd_next_incoming(&result));

    // Local reject is retained separately from an unanswered caller hangup.
    current = 0; state.call = 1; incoming_outcome = 1;
    assert(sd_hangup() == PJ_SUCCESS);
    emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    assert(sd_next_incoming(&result) && result.outcome == 2);

    // A connected incoming call is never marked missed; repeated confirmed
    // callbacks must not reset its monotonic start time.
    current = 0; state.call = 2; incoming_outcome = 3;
    emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_CONFIRMED);
    struct timespec start = connected_at;
    emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_CONFIRMED);
    assert(start.tv_sec == connected_at.tv_sec && start.tv_nsec == connected_at.tv_nsec);
    emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    assert(sd_next_incoming(&result) && result.outcome == 3);
    assert(sd_state().connected_seconds == 0);
    assert(elapsed_seconds((struct timespec){100, 900000000}, (struct timespec){102, 100000000}) == 1);
    assert(elapsed_seconds((struct timespec){100, 0}, (struct timespec){90, 0}) == 0);

    // Queue overload discards oldest events, with bounded storage and no
    // duplicate delivery. Ordinary polling drains this queue every 100 ms.
    for (int i = 0; i < 35; i++) {
        current = 0; state.call = 1; incoming_outcome = 1;
        emit(0, PJSIP_ROLE_UAS, PJSIP_INV_STATE_DISCONNECTED);
    }
    int delivered = 0;
    while (sd_next_incoming(&result)) delivered++;
    assert(delivered == 32);
    assert(sd_next_incoming(NULL) == 0);
    state.call = 3;
    assert(sd_refresh() == PJ_EBUSY);
    state.call = 0;

    // Account transition freezes incoming admission under the same mutex as
    // call ownership; an existing call rejects transition without changing it.
    current = 0; state.call = 1; stopping = 0;
    assert(sd_prepare_connect() == PJ_EBUSY && !stopping && current == 0);
    current = PJSUA_INVALID_ID; state.call = 0;
    incoming_outcome = 1;
    completed_incoming();
    assert(sd_prepare_connect() == PJ_SUCCESS && stopping);
    account = 9;
    memset(&observed, 0, sizeof(observed));
    observed.id = 0;
    observed.remote_info = pj_str("sip:late@example.test");
    incoming(9, 0, NULL);
    assert(answered_code == 486 && current == PJSUA_INVALID_ID && !state.call);
    assert(sd_next_incoming(&result) && result.outcome == 1);
    assert(!sd_next_incoming(&result));

    puts("Passed incoming outcomes, event retention, monotonic duration, recovery guard and outgoing reservation race:\nrejected incoming callbacks cannot steal tracking; hangup targets outgoing call.");
    return 0;
}
