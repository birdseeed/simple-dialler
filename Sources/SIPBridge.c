#include "SIPBridge.h"
#include <pjsua-lib/pjsua.h>
#include <pthread.h>
#include <stdio.h>
#include <string.h>
#include <time.h>

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static SDState state;
static int created, stopping;
static pjsua_acc_id account = PJSUA_INVALID_ID;
static pjsua_call_id current = PJSUA_INVALID_ID;
static char domain[260];
static int incoming_outcome;
static struct timespec connected_at;
static SDIncomingResult incoming_results[32];
static unsigned incoming_head, incoming_count;
static int audio_input = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
static int audio_output = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
static int checking_audio;
static pj_pool_t *check_pool;
static pjmedia_port *check_port;
static pjsua_conf_port_id check_slot = PJSUA_INVALID_ID;

static unsigned long long elapsed_seconds(struct timespec start, struct timespec end) {
    if (!start.tv_sec || end.tv_sec < start.tv_sec) return 0;
    time_t seconds = end.tv_sec - start.tv_sec;
    if (end.tv_nsec < start.tv_nsec && seconds > 0) seconds--;
    return (unsigned long long)seconds;
}

static void completed_incoming(void) {
    if (!incoming_outcome) return;
    if (incoming_count == 32) { incoming_head = (incoming_head + 1) % 32; incoming_count--; }
    SDIncomingResult *result = &incoming_results[(incoming_head + incoming_count++) % 32];
    result->outcome = incoming_outcome;
    memcpy(result->remote, state.remote, sizeof(result->remote));
    incoming_outcome = 0;
}

int sd_next_incoming(SDIncomingResult *result) {
    if (!result) return 0;
    pthread_mutex_lock(&lock);
    int available = incoming_count != 0;
    if (available) { *result = incoming_results[incoming_head]; incoming_head = (incoming_head + 1) % 32; incoming_count--; }
    pthread_mutex_unlock(&lock);
    return available;
}

static void no_log(int level, const char *data, int length) {
    (void)level; (void)data; (void)length;
}

static void copy_remote(const pj_str_t *remote) {
    size_t n = remote->slen < 255 ? (size_t)remote->slen : 255;
    for (size_t i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)remote->ptr[i];
        state.remote[i] = c < 32 || c == 127 ? ' ' : (char)c;
    }
    state.remote[n] = '\0';
}

static void registration_changed(pjsua_acc_id id) {
    pjsua_acc_info info;
    if (pjsua_acc_get_info(id, &info) != PJ_SUCCESS) return;
    pthread_mutex_lock(&lock);
    if (!stopping) {
        state.registration_code = info.status;
        state.registration = info.status == 200 && info.expires > 0 ? 2 :
            (info.status >= 300 ? 3 : 1);
    }
    pthread_mutex_unlock(&lock);
}

static void call_changed(pjsua_call_id id, pjsip_event *event) {
    (void)event;
    pjsua_call_info info;
    if (pjsua_call_get_info(id, &info) != PJ_SUCCESS) return;
    pthread_mutex_lock(&lock);
    // -2 reserves the sole outgoing call while make_call creates it. PJ reports
    // its native UAC role in call_info before invoking on_call_state. Rejected
    // incoming (UAS) callbacks must never adopt or clear this reservation.
    if (!stopping && (current == id || (current == -2 && info.role == PJSIP_ROLE_UAC))) {
        current = id;
        copy_remote(&info.remote_info);
        state.call_code = info.last_status;
        if (info.state == PJSIP_INV_STATE_DISCONNECTED) {
            completed_incoming();
            current = PJSUA_INVALID_ID;
            state.call = 0;
            state.muted = 0;
        } else if (info.state == PJSIP_INV_STATE_CONFIRMED) {
            if (state.call != 3) clock_gettime(CLOCK_MONOTONIC, &connected_at);
            state.call = 3;
        }
    }
    pthread_mutex_unlock(&lock);
}

static void incoming(pjsua_acc_id id, pjsua_call_id call, pjsip_rx_data *data) {
    (void)data;
    pjsua_call_info info;
    if (pjsua_call_get_info(call, &info) != PJ_SUCCESS) return;
    pthread_mutex_lock(&lock);
    int accept = !stopping && id == account && current == PJSUA_INVALID_ID;
    if (accept) {
        current = call;
        incoming_outcome = 1;
        memset(&connected_at, 0, sizeof(connected_at));
        state.call = 1;
        state.call_code = 180;
        state.muted = 0;
        state.call_generation++;
        copy_remote(&info.remote_info);
    }
    pthread_mutex_unlock(&lock);
    pjsua_call_answer(call, accept ? 180 : 486, NULL, NULL);
}

static void media_changed(pjsua_call_id id) {
    pjsua_call_info info;
    if (pjsua_call_get_info(id, &info) != PJ_SUCCESS) return;
    pthread_mutex_lock(&lock);
    int active = !stopping && current == id && state.call != 1;
    pthread_mutex_unlock(&lock);
    if (active && info.media_status == PJSUA_CALL_MEDIA_ACTIVE) {
        pjsua_conf_connect(info.conf_slot, 0);
        pjsua_conf_connect(0, info.conf_slot);
    }
}

static void subscribe(pjsua_acc_id id, pjsua_srv_pres *presence,
                      pjsua_buddy_id buddy, const pj_str_t *from,
                      pjsip_rx_data *data, pjsip_status_code *code,
                      pj_str_t *reason, pjsua_msg_data *message) {
    (void)id; (void)presence; (void)buddy; (void)from;
    (void)data; (void)reason; (void)message;
    *code = PJSIP_SC_FORBIDDEN;
}

static void transfer_requested(pjsua_call_id id, const pj_str_t *destination,
                               pjsip_status_code *code) {
    (void)id; (void)destination;
    *code = PJSIP_SC_FORBIDDEN;
}

static void replacement_requested(pjsua_call_id id, pjsip_rx_data *data,
                                  int *code, pj_str_t *reason) {
    (void)id; (void)data; (void)reason;
    *code = PJSIP_SC_FORBIDDEN;
}

static pjsip_redirect_op redirected(pjsua_call_id id, const pjsip_uri *target,
                                    const pjsip_event *event) {
    (void)id; (void)target; (void)event;
    return PJSIP_REDIRECT_STOP;
}

SDState sd_state(void) {
    pthread_mutex_lock(&lock);
    SDState result = state;
    if (state.call == 3) {
        struct timespec now;
        clock_gettime(CLOCK_MONOTONIC, &now);
        result.connected_seconds = elapsed_seconds(connected_at, now);
    } else result.connected_seconds = 0;
    pthread_mutex_unlock(&lock);
    return result;
}

int sd_start(void) {
    if (created) return PJ_SUCCESS;
    pj_log_set_level(0);
    pj_log_set_log_func(no_log);
    pj_status_t result = pjsua_create();
    if (result != PJ_SUCCESS) return result;
    created = 1;
    pthread_mutex_lock(&lock);
    stopping = 0;
    memset(&state, 0, sizeof(state));
    pthread_mutex_unlock(&lock);
    pjsua_config config;
    pjsua_config_default(&config);
    config.max_calls = 2; // The second slot exists only to send Busy Here.
    config.thread_cnt = 1;
    config.user_agent = pj_str("SimpleDialler/1.0");
    config.cb.on_reg_state = registration_changed;
    config.cb.on_incoming_call = incoming;
    config.cb.on_call_state = call_changed;
    config.cb.on_call_media_state = media_changed;
    config.cb.on_incoming_subscribe = subscribe;
    config.cb.on_call_transfer_request = transfer_requested;
    config.cb.on_call_replace_request = replacement_requested;
    config.cb.on_call_redirected = redirected;
    pjsua_logging_config logging;
    pjsua_logging_config_default(&logging);
    logging.level = 0;
    logging.console_level = 0;
    logging.msg_logging = PJ_FALSE;
    logging.cb = no_log;
    pjsua_media_config media;
    pjsua_media_config_default(&media);
    media.snd_auto_close_time = 1;
    result = pjsua_init(&config, &logging, &media);
    if (result == PJ_SUCCESS) {
        pjsua_transport_config transport;
        pjsua_transport_config_default(&transport);
        transport.port = 0; // Let the OS choose, so Zoiper can stay open.
        result = pjsua_transport_create(PJSIP_TRANSPORT_UDP, &transport, NULL);
    }
    if (result == PJ_SUCCESS) result = pjsua_start();
    if (result != PJ_SUCCESS) { sd_stop(); return result; }
    pthread_mutex_lock(&lock);
    state.running = 1;
    pthread_mutex_unlock(&lock);
    return PJ_SUCCESS;
}

void sd_stop(void) {
    if (!created) return;
    pthread_mutex_lock(&lock);
    stopping = 1;
    pthread_mutex_unlock(&lock);
    sd_audio_check(0);
    // Joins PJ worker threads before resetting their shared state.
    pjsua_destroy();
    created = 0;
    pthread_mutex_lock(&lock);
    account = PJSUA_INVALID_ID;
    current = PJSUA_INVALID_ID;
    memset(&state, 0, sizeof(state));
    memset(domain, 0, sizeof(domain));
    incoming_outcome = 0;
    memset(&connected_at, 0, sizeof(connected_at));
    checking_audio = 0;
    audio_input = PJMEDIA_AUD_DEFAULT_CAPTURE_DEV;
    audio_output = PJMEDIA_AUD_DEFAULT_PLAYBACK_DEV;
    pthread_mutex_unlock(&lock);
}

static int safe_token(const char *value, const char *allowed, size_t max) {
    return value && value[0] && strlen(value) <= max && strspn(value, allowed) == strlen(value);
}

int sd_prepare_connect(void) {
    pthread_mutex_lock(&lock);
    int result = current == PJSUA_INVALID_ID ? PJ_SUCCESS : PJ_EBUSY;
    if (result == PJ_SUCCESS) stopping = 1; // Freeze incoming admission before draining old-account events.
    pthread_mutex_unlock(&lock);
    return result;
}

int sd_connect(const char *server, const char *username, const char *password) {
    if (!safe_token(server, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:", 253) ||
        !safe_token(username, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.+-*", 128) ||
        !password || !password[0] || strlen(password) > 512) return PJ_EINVAL;
    int admission = sd_prepare_connect();
    if (admission != PJ_SUCCESS) return admission;
    sd_stop();
    pj_status_t result = sd_start();
    if (result != PJ_SUCCESS) return result;
    snprintf(domain, sizeof(domain), "%s", server);
    char identity[420], registrar[280];
    snprintf(identity, sizeof(identity), "sip:%s@%s", username, server);
    snprintf(registrar, sizeof(registrar), "sip:%s;transport=udp", server);
    pjsua_acc_config config;
    pjsua_acc_config_default(&config);
    config.id = pj_str(identity);
    config.reg_uri = pj_str(registrar);
    config.cred_count = 1;
    config.cred_info[0].realm = pj_str("*");
    config.cred_info[0].scheme = pj_str("digest");
    config.cred_info[0].username = pj_str((char *)username);
    config.cred_info[0].data_type = PJSIP_CRED_DATA_PLAIN_PASSWD;
    config.cred_info[0].data = pj_str((char *)password);
    config.publish_enabled = PJ_FALSE;
    config.mwi_enabled = PJ_FALSE;
    config.vid_in_auto_show = PJ_FALSE;
    config.vid_out_auto_transmit = PJ_FALSE;
    config.use_srtp = PJMEDIA_SRTP_DISABLED; // Existing Voipfone UDP account.
    config.rtp_cfg.port = 0;
    config.reg_retry_interval = 30;
    config.reg_first_retry_interval = 5;
    config.ka_interval = 15;
    pthread_mutex_lock(&lock);
    state.registration = 1;
    pthread_mutex_unlock(&lock);
    pjsua_acc_id new_account = PJSUA_INVALID_ID;
    result = pjsua_acc_add(&config, PJ_TRUE, &new_account);
    pthread_mutex_lock(&lock);
    account = new_account;
    pthread_mutex_unlock(&lock);
    if (result != PJ_SUCCESS) {
        pthread_mutex_lock(&lock);
        state.registration = 3;
        state.registration_code = result;
        pthread_mutex_unlock(&lock);
    }
    return result;
}

int sd_call(const char *number) {
    if (!safe_token(number, "+0123456789*#", 64)) return PJ_EINVAL;
    if (strchr(number + 1, '+') || (number[0] == '+' && !number[1])) return PJ_EINVAL;
    pthread_mutex_lock(&lock);
    if (!state.running || state.registration != 2 || current != PJSUA_INVALID_ID) {
        pthread_mutex_unlock(&lock); return PJ_EINVALIDOP;
    }
    current = -2;
    state.call = 2;
    state.call_code = 0;
    state.muted = 0;
    state.call_generation++;
    memset(&connected_at, 0, sizeof(connected_at));
    pthread_mutex_unlock(&lock);
    pjsua_conf_adjust_rx_level(0, 1.0f);
    // '#' must be URI escaped; accepting arbitrary SIP URIs is deliberately unsupported.
    char escaped[193], destination[500];
    size_t out = 0;
    for (size_t i = 0; number[i]; ++i) {
        if (number[i] == '#') { memcpy(escaped + out, "%23", 3); out += 3; }
        else escaped[out++] = number[i];
    }
    escaped[out] = 0;
    snprintf(destination, sizeof(destination), "sip:%s@%s;transport=udp", escaped, domain);
    pj_str_t uri = pj_str(destination);
    pjsua_call_setting settings;
    pjsua_call_setting_default(&settings);
    settings.aud_cnt = 1;
    settings.vid_cnt = 0;
    pjsua_call_id call = PJSUA_INVALID_ID;
    pj_status_t result = pjsua_call_make_call(account, &uri, &settings, NULL, NULL, &call);
    pthread_mutex_lock(&lock);
    if (result != PJ_SUCCESS) { current = PJSUA_INVALID_ID; state.call = 0; }
    else if (current == -2) current = call;
    pthread_mutex_unlock(&lock);
    return result;
}

int sd_answer(void) {
    pthread_mutex_lock(&lock);
    int call = current;
    int valid = state.call == 1 && call >= 0;
    if (valid) { state.call = 2; incoming_outcome = 3; }
    pthread_mutex_unlock(&lock);
    if (!valid) return PJ_EINVALIDOP;
    pjsua_conf_adjust_rx_level(0, 1.0f);
    pjsua_call_setting settings;
    pjsua_call_setting_default(&settings);
    settings.aud_cnt = 1;
    settings.vid_cnt = 0;
    int result = pjsua_call_answer2(call, &settings, 200, NULL, NULL);
    if (result != PJ_SUCCESS) {
        pthread_mutex_lock(&lock);
        if (current == call && state.call == 2) { state.call = 1; incoming_outcome = 1; }
        pthread_mutex_unlock(&lock);
    }
    return result;
}

int sd_hangup(void) {
    pthread_mutex_lock(&lock);
    int call = current;
    int code = state.call == 1 ? 486 : 0;
    if (code) incoming_outcome = 2;
    pthread_mutex_unlock(&lock);
    int result = call >= 0 ? pjsua_call_hangup(call, code, NULL, NULL) : PJ_EINVALIDOP;
    if (result != PJ_SUCCESS && code) {
        pthread_mutex_lock(&lock);
        if (current == call && state.call == 1) incoming_outcome = 1;
        pthread_mutex_unlock(&lock);
    }
    return result;
}

int sd_dtmf(char digit) {
    if (!strchr("0123456789*#", digit) || !digit) return PJ_EINVAL;
    pthread_mutex_lock(&lock);
    int call = state.call == 3 ? current : PJSUA_INVALID_ID;
    pthread_mutex_unlock(&lock);
    char buffer[2] = {digit, 0};
    pj_str_t digits = pj_str(buffer);
    return call >= 0 ? pjsua_call_dial_dtmf(call, &digits) : PJ_EINVALIDOP;
}

int sd_mute(int muted) {
    if (sd_state().call != 3) return PJ_EINVALIDOP;
    int result = pjsua_conf_adjust_rx_level(0, muted ? 0.0f : 1.0f);
    if (result == PJ_SUCCESS) {
        pthread_mutex_lock(&lock);
        state.muted = !!muted;
        pthread_mutex_unlock(&lock);
    }
    return result;
}

int sd_refresh(void) {
    if (sd_state().call != 0) return PJ_EBUSY;
    return created && account != PJSUA_INVALID_ID ? pjsua_acc_set_registration(account, PJ_TRUE) : PJ_EINVALIDOP;
}


int sd_audio_devices(SDAudioDevice *devices, int capacity) {
    if (!created || !devices || capacity <= 0) return 0;
    // Re-enumeration is only safe while idle, never tear down call audio here.
    if (sd_state().call == 0 && !checking_audio) pjmedia_aud_dev_refresh();
    unsigned count = pjmedia_aud_dev_count();
    int found = 0;
    for (unsigned i = 0; i < count && found < capacity; i++) {
        pjmedia_aud_dev_info info;
        if (pjmedia_aud_dev_get_info(i, &info) != PJ_SUCCESS) continue;
        SDAudioDevice *device = &devices[found++];
        device->id = (int)i;
        device->inputs = (int)info.input_count;
        device->outputs = (int)info.output_count;
        snprintf(device->name, sizeof(device->name), "%s", info.name);
    }
    return found;
}

static int configure_audio(int input, int output) {
    pjmedia_aud_dev_info info;
    if (input >= 0 && (pjmedia_aud_dev_get_info(input, &info) != PJ_SUCCESS || !info.input_count)) return PJ_EINVAL;
    if (output >= 0 && (pjmedia_aud_dev_get_info(output, &info) != PJ_SUCCESS || !info.output_count)) return PJ_EINVAL;
    audio_input = input;
    audio_output = output;
    pjsua_snd_dev_param param;
    pjsua_snd_dev_param_default(&param);
    param.capture_dev = input;
    param.playback_dev = output;
    param.mode = PJSUA_SND_DEV_NO_IMMEDIATE_OPEN;
    return pjsua_set_snd_dev2(&param);
}

int sd_audio_select(int input, int output) {
    if (!created || sd_state().call != 0 || checking_audio) return PJ_EINVALIDOP;
    return configure_audio(input, output);
}

static pj_status_t discard_frame(pjmedia_port *port, pjmedia_frame *frame) {
    (void)port; (void)frame;
    return PJ_SUCCESS;
}

static pj_status_t destroy_check_port(pjmedia_port *port) {
    pj_pool_release((pj_pool_t *)port->port_data.pdata);
    return PJ_SUCCESS;
}

static int create_check_port(void) {
    check_pool = pjsua_pool_create("local-mic-check", 1024, 1024);
    if (!check_pool) return PJ_ENOMEM;
    check_port = PJ_POOL_ZALLOC_T(check_pool, pjmedia_port);
    pj_str_t name = pj_str("local-mic-discard");
    pjmedia_port_info_init(&check_port->info, &name, PJMEDIA_SIG_CLASS_PORT_AUD('L', 'M'), 16000, 1, 16, 320);
    check_port->put_frame = discard_frame;
    check_port->on_destroy = destroy_check_port;
    check_port->port_data.pdata = check_pool;
    int result = pjmedia_port_init_grp_lock(check_port, check_pool, NULL);
    if (result != PJ_SUCCESS) {
        pj_pool_release(check_pool); check_pool = NULL; check_port = NULL;
    }
    return result;
}

int sd_audio_check(int enabled) {
    if (!created || (enabled && sd_state().call != 0)) return PJ_EINVALIDOP;
    if (enabled) {
        if (checking_audio) return PJ_SUCCESS;
        int result = create_check_port();
        if (result != PJ_SUCCESS) return result;
        if (result == PJ_SUCCESS) result = pjsua_conf_add_port(check_pool, check_port, &check_slot);
        if (result == PJ_SUCCESS) result = pjsua_set_snd_dev(audio_input, audio_output);
        // A private null sink keeps input metering active. Never connect the
        // microphone to playback or to a remote call for this local check.
        if (result == PJ_SUCCESS) result = pjsua_conf_connect(0, check_slot);
        checking_audio = 1; // Also permits cleanup of partial setup failures.
        if (result != PJ_SUCCESS) sd_audio_check(0);
        return result;
    }
    if (checking_audio) {
        if (check_slot != PJSUA_INVALID_ID) {
            pjsua_conf_disconnect(0, check_slot);
            pjsua_conf_remove_port(check_slot);
        }
        // Drop our reference; the conference bridge retains its own reference
        // until asynchronous removal finishes. Only the port destructor frees
        // its pool, including partial setup and engine teardown paths.
        if (check_port) pjmedia_port_destroy(check_port);
        check_pool = NULL;
        check_port = NULL;
        check_slot = PJSUA_INVALID_ID;
        pjsua_set_no_snd_dev();
        checking_audio = 0;
        return configure_audio(audio_input, audio_output);
    }
    return PJ_SUCCESS;
}

int sd_audio_level(void) {
    unsigned tx = 0, rx = 0;
    if (!checking_audio || sd_state().call != 0) return 0;
    if (pjsua_conf_get_signal_level(0, &tx, &rx) != PJ_SUCCESS) return 0;
    return (int)rx;
}
