# LAN Guard host checks

`./tests/lan-guard/run.sh [patched-Bruce-path]` tests the DHCP option parser,
truncated/malformed packets, arbitrary inputs under ASan/UBSan, gateway MAC
baseline changes and wrap-safe alert sampling. The socket path and ESP32 Wi-Fi
stack are not exercised.

LAN Guard observes the STA ARP cache rather than all ARP packets. A change in
the gateway MAC or DHCP server differing from the gateway is an observation,
not proof of an attack. DHCP servers/relays may legitimately differ; DHCP
comparison is disabled in AP+STA mode because this UDP API does not identify
which interface received a packet. Binding UDP 68 does not guarantee capture,
and it may fail because the STA DHCP client already owns the port. Oversized
or malformed packets are ignored. A detected disconnect, gateway or BSSID
change resets the baseline; changes missed between polls cannot be detected.
Observation counters count all samples, while flash alerts are rate-limited
and periodic state is persisted every 30 seconds to reduce flash writes.
