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
    unsigned long long connected_seconds;
    char remote[256];
} SDState;

typedef struct {
    int outcome; // 1 missed, 2 rejected, 3 answered
    char remote[256];
} SDIncomingResult;
// Bounded queue retains completed incoming events between UI polls.
int sd_next_incoming(SDIncomingResult *result);
typedef struct {
    int id;
    int inputs;
    int outputs;
    char name[128];
} SDAudioDevice;
int sd_audio_devices(SDAudioDevice *devices, int capacity);
int sd_audio_select(int input, int output);
int sd_audio_check(int enabled);
int sd_audio_level(void);
int sd_start(void);
int sd_prepare_connect(void);
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
