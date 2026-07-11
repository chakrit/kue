import "net"

// net package IP string-validator surface (STDLIB-NET). Only success cases live here —
// non-conforming inputs (a validator conflict is a cue export error, no json) are pinned
// by native_decide in NetTests.lean.
ipv4:       net.IPv4 & "127.0.0.1"
ipv6:       net.IPv6 & "2001:db8::1"
ip_any:     net.IP & "::ffff:1.2.3.4"
cidr:       net.IPCIDR & "10.0.0.0/8"
loopback:   net.LoopbackIP & "127.0.0.1"
multicast:  net.MulticastIP & "224.0.0.1"
ll_unicast: net.LinkLocalUnicastIP & "169.254.1.1"
global:     net.GlobalUnicastIP & "8.8.8.8"
v4len:      net.IPv4len
v6len:      net.IPv6len
is_v4:      net.IPv4("1.2.3.4")
not_v4:     net.IPv4("bad")
is_cidr:    net.IPCIDR("192.168.0.0/16")
