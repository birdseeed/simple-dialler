#ifndef SIMPLE_DIALLER_BRIDGE_H
#define SIMPLE_DIALLER_BRIDGE_H

// Public functions run on the app's main thread. PJ callbacks never enter Swift.
// State is copied under a mutex and polled by the main thread.
typedef struct {
    int running;
    int registration; // 0 offline, 1 connecting, 2 registered, 3 error
    int registration_code;
    int call;         // 0 idle, 1 incoming, 2 dialling, 3 connected
    int call_code;
    int muted;
    unsigned int call_generation;
    char remote[256];
} SDState;

int sd_start(void);
int sd_connect(const char *server, const char *username, const char *password);
void sd_stop(void);
SDState sd_state(void);
int sd_call(const char *number);
int sd_answer(void);
int sd_hangup(void);
int sd_dtmf(char digit);
int sd_mute(int muted);
int sd_refresh(void);
#endif
