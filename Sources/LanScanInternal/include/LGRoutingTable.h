//
//  LGRoutingTable.h
//  LanScanInternal
//
//  Two reads of the kernel routing table that Swift cannot do alone: the iOS SDK does not
//  ship <net/route.h>, so the message layouts live in the .c file.
//

#ifndef LGRoutingTable_h
#define LGRoutingTable_h

#include <stdbool.h>
#include <stdint.h>

/// Looks the IPv4 address up in the ARP cache (the routing table's link-layer entries).
/// `ipv4` is in network byte order. Returns `true` and fills `mac` when the kernel knows
/// the hardware address, i.e. after the device answered a ping.
bool LGRoutingTableMACAddress(uint32_t ipv4, uint8_t mac[6]);

/// The default IPv4 gateway reached through `interfaceName` ("en0" for Wi-Fi), in network
/// byte order. Returns `false` when there is none.
bool LGRoutingTableDefaultGateway(const char *interfaceName, uint32_t *gateway);

#endif
