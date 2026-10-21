#include "SIPBridge.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    for (int i = 0; i < 3; ++i) {
        assert(sd_start() == 0);
        SDState state = sd_state();
        assert(state.running && !state.registration && !state.call);
        assert(sd_call("123") != 0); // Cannot dial without a registered account.
        assert(sd_call("123@evil.test") != 0);
        assert(sd_answer() != 0);
        assert(sd_dtmf('1') != 0);
        assert(sd_mute(1) != 0);
        assert(sd_connect("evil.test;transport=tcp", "dummy", "dummy") != 0);
        sd_stop();
        assert(!sd_state().running);
        sd_stop(); // Idempotent teardown.
    }
    puts("Passed three SIP engine start/stop cycles and offline guards. No account, audio or calls opened.");
    return 0;
}
