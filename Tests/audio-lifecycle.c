// Replace only physical sound-device opening with PJ's null sound clock.
// Real conference/group-lock lifecycle executes; no account or hardware opens.
#define pjsua_set_snd_dev simulated_set_snd_dev
#include "../Sources/SIPBridge.c"
#include <assert.h>
#include <stdatomic.h>
static atomic_int destroyed;

pj_status_t simulated_set_snd_dev(int input, int output) {
    (void)input; (void)output;
    return pjsua_set_null_snd_dev();
}

static void observed_destroy(void *ignored) {
    (void)ignored;
    atomic_fetch_add(&destroyed, 1);
}

int main(void) {
    assert(sd_start() == PJ_SUCCESS);
    for (int i = 0; i < 12; i++) {
        assert(sd_audio_check(1) == PJ_SUCCESS);
        assert(check_port && checking_audio);
        assert(pjmedia_port_add_destroy_handler(check_port, NULL, observed_destroy) == PJ_SUCCESS);
        // Include immediate stop before async add completes and a stop after
        // media has ticked. Both must defer memory release until references end.
        if (i % 2) pj_thread_sleep(40);
        assert(sd_audio_check(0) == PJ_SUCCESS);
        assert(!checking_audio && !check_pool && !check_port);
        assert(sd_audio_check(0) == PJ_SUCCESS);
        assert(sd_audio_level() == 0);
    }
    // Destroy flushes pending conference operations even if stop removed the
    // null clock immediately. All twelve ports must be destroyed exactly once.
    incoming_outcome = 1;
    snprintf(state.remote, sizeof(state.remote), "sip:old-account@example.test");
    completed_incoming();
    sd_stop();
    SDIncomingResult old;
    assert(sd_next_incoming(&old) && strcmp(old.remote, "sip:old-account@example.test") == 0);
    assert(atomic_load(&destroyed) == 12);
    assert(sd_audio_check(0) != PJ_SUCCESS); // Safe after full teardown.
    puts("Passed twelve real local audio-port start/stop lifecycles on null clock; exactly-once deferred destruction, no physical devices.");
    return 0;
}
