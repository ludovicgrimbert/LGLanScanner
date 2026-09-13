//
//  LGRoutingTable.c
//  LanScanInternal
//

#include "LGRoutingTable.h"

#include <net/if.h>
#include <net/if_dl.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <unistd.h>

// Routing-socket message layout and constants from xnu's <net/route.h> (APSL 2.0), which
// the iOS SDK does not expose. Field order and sizes must match the kernel's exactly.
struct lg_rt_metrics {
    uint32_t rmx_locks, rmx_mtu, rmx_hopcount;
    int32_t  rmx_expire;
    uint32_t rmx_recvpipe, rmx_sendpipe, rmx_ssthresh, rmx_rtt, rmx_rttvar, rmx_pksent, rmx_state;
    uint32_t rmx_filler[3];
};

struct lg_rt_msghdr {
    u_short  rtm_msglen;
    u_char   rtm_version;
    u_char   rtm_type;
    u_short  rtm_index;
    int      rtm_flags;
    int      rtm_addrs;
    pid_t    rtm_pid;
    int      rtm_seq;
    int      rtm_errno;
    int      rtm_use;
    uint32_t rtm_inits;
    struct lg_rt_metrics rtm_rmx;
};

#define LG_RTM_VERSION 5
#define LG_RTM_GET     0x4
#define LG_RTA_DST     0x1
#define LG_RTA_GATEWAY 0x2
#define LG_RTAX_DST    0
#define LG_RTAX_GATEWAY 1
#define LG_RTAX_MAX    8
#define LG_RTF_GATEWAY 0x2
#define LG_RTF_LLINFO  0x400
#define LG_NET_RT_FLAGS 2
// Socket addresses in routing messages are 4-byte aligned on Darwin.
#define LG_ROUNDUP(a) ((a) > 0 ? (1 + (((a) - 1) | (sizeof(uint32_t) - 1))) : sizeof(uint32_t))

/// Walks the socket addresses that follow a routing message header into `table`, indexed
/// by RTAX_*; entries absent from `rtm_addrs` are NULL.
static void lg_parse_sockaddrs(const struct lg_rt_msghdr *rtm, const uint8_t *end, const struct sockaddr *table[LG_RTAX_MAX]) {
    const uint8_t *p = (const uint8_t *)(rtm + 1);
    for (int i = 0; i < LG_RTAX_MAX; i++) {
        table[i] = NULL;
        if (!(rtm->rtm_addrs & (1 << i))) continue;
        if (p + sizeof(struct sockaddr) > end) break;
        const struct sockaddr *sa = (const struct sockaddr *)p;
        table[i] = sa;
        p += LG_ROUNDUP(sa->sa_len);
    }
}

bool LGRoutingTableMACAddress(uint32_t ipv4, uint8_t mac[6]) {
    int fd = socket(PF_ROUTE, SOCK_RAW, 0);
    if (fd < 0) return false;

    uint8_t buffer[sizeof(struct lg_rt_msghdr) + 512];
    memset(buffer, 0, sizeof(buffer));
    struct lg_rt_msghdr *rtm = (struct lg_rt_msghdr *)buffer;
    struct sockaddr_in *sin = (struct sockaddr_in *)(rtm + 1);

    const pid_t pid = getpid();
    const int seq = (int)(ipv4 & 0x7fffffff) | 1;
    rtm->rtm_msglen = sizeof(*rtm) + sizeof(*sin);
    rtm->rtm_version = LG_RTM_VERSION;
    rtm->rtm_type = LG_RTM_GET;
    rtm->rtm_addrs = LG_RTA_DST;
    rtm->rtm_flags = LG_RTF_LLINFO;
    rtm->rtm_pid = pid;
    rtm->rtm_seq = seq;
    sin->sin_len = sizeof(*sin);
    sin->sin_family = AF_INET;
    sin->sin_addr.s_addr = ipv4;

    if (write(fd, rtm, rtm->rtm_msglen) < 0) {
        close(fd);
        return false;
    }

    // The socket also receives every other process's routing traffic: keep reading until
    // our own answer shows up, within reason.
    ssize_t n = -1;
    for (int attempt = 0; attempt < 16; attempt++) {
        n = read(fd, buffer, sizeof(buffer));
        if (n < (ssize_t)sizeof(*rtm)) { n = -1; break; }
        if (rtm->rtm_seq == seq && rtm->rtm_pid == pid) break;
        n = -1;
    }
    close(fd);
    if (n < 0 || rtm->rtm_errno != 0) return false;

    const struct sockaddr *table[LG_RTAX_MAX];
    lg_parse_sockaddrs(rtm, buffer + n, table);
    const struct sockaddr *gateway = table[LG_RTAX_GATEWAY];
    if (gateway == NULL || gateway->sa_family != AF_LINK) return false;

    const struct sockaddr_dl *sdl = (const struct sockaddr_dl *)gateway;
    if (sdl->sdl_alen != 6) return false;
    memcpy(mac, LLADDR(sdl), 6);
    static const uint8_t zero[6] = {0};
    return memcmp(mac, zero, 6) != 0;
}

bool LGRoutingTableDefaultGateway(const char *interfaceName, uint32_t *gateway) {
    int mib[] = { CTL_NET, PF_ROUTE, 0, AF_INET, LG_NET_RT_FLAGS, LG_RTF_GATEWAY };
    size_t length = 0;
    if (sysctl(mib, sizeof(mib) / sizeof(int), NULL, &length, NULL, 0) < 0 || length == 0) return false;

    uint8_t *buffer = malloc(length);
    if (buffer == NULL) return false;
    if (sysctl(mib, sizeof(mib) / sizeof(int), buffer, &length, NULL, 0) < 0) {
        free(buffer);
        return false;
    }

    bool found = false;
    for (uint8_t *p = buffer; p + sizeof(struct lg_rt_msghdr) <= buffer + length && !found;) {
        const struct lg_rt_msghdr *rtm = (const struct lg_rt_msghdr *)p;
        if (rtm->rtm_msglen == 0) break;

        const struct sockaddr *table[LG_RTAX_MAX];
        lg_parse_sockaddrs(rtm, p + rtm->rtm_msglen, table);
        const struct sockaddr *dst = table[LG_RTAX_DST];
        const struct sockaddr *gw = table[LG_RTAX_GATEWAY];

        if (dst && gw && dst->sa_family == AF_INET && gw->sa_family == AF_INET
            && ((const struct sockaddr_in *)dst)->sin_addr.s_addr == 0) {  // the default route
            char name[IF_NAMESIZE] = {0};
            if (if_indextoname(rtm->rtm_index, name) != NULL && strcmp(name, interfaceName) == 0) {
                *gateway = ((const struct sockaddr_in *)gw)->sin_addr.s_addr;
                found = true;
            }
        }
        p += rtm->rtm_msglen;
    }
    free(buffer);
    return found;
}
