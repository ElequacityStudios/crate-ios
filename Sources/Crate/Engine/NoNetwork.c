/* Stand-ins for the seven libslirp functions crate calls, until crate-ios has
   networking of its own. crate links libslirp for user-mode networking, and on
   iOS leaves it to the app; libslirp needs GLib, which the app doesn't ship
   yet. With these, starting networking fails the way crate expects a failure:
   slirp_new returns NULL, crate logs that it could not start user-mode
   networking, and the VM runs without a network. */

#include <stddef.h>
#include <stdint.h>

typedef struct Slirp Slirp;
struct in_addr;

Slirp *slirp_new(const void *cfg, const void *callbacks, void *opaque) {
    (void)cfg;
    (void)callbacks;
    (void)opaque;
    return NULL;
}

void slirp_cleanup(Slirp *slirp) { (void)slirp; }

void slirp_pollfds_fill_socket(Slirp *slirp, uint32_t *timeout, void *add_poll, void *opaque) {
    (void)slirp;
    (void)timeout;
    (void)add_poll;
    (void)opaque;
}

void slirp_pollfds_poll(Slirp *slirp, int select_error, void *get_revents, void *opaque) {
    (void)slirp;
    (void)select_error;
    (void)get_revents;
    (void)opaque;
}

void slirp_input(Slirp *slirp, const uint8_t *pkt, int pkt_len) {
    (void)slirp;
    (void)pkt;
    (void)pkt_len;
}

int slirp_add_hostfwd(Slirp *slirp, int is_udp, uint32_t host_addr, int host_port,
                      uint32_t guest_addr, int guest_port) {
    (void)slirp;
    (void)is_udp;
    (void)host_addr;
    (void)host_port;
    (void)guest_addr;
    (void)guest_port;
    return -1;
}

const char *slirp_version_string(void) { return "none (crate-ios has no network yet)"; }
