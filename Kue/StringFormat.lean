import Kue.Time
import Kue.Net

namespace Kue

/-- Whether `value` satisfies the string-format validator `fmt`. The single predicate behind
    every `time.*`/`net.*` string validator's meet against a concrete string; the domain
    predicates live in `Kue/Time.lean` and `Kue/Net.lean`, this leaf joins them. Exhaustive
    over `StringFormat`, so a new validator surface forces a dispatch decision here rather
    than silently passing. -/
def stringFormatValid : StringFormat → String → Bool
  | .duration => isValidDuration
  | .rfc3339 => isValidRFC3339
  | .netIP => isNetIP
  | .netIPv4 => isNetIPv4
  | .netIPv6 => isNetIPv6
  | .netIPCIDR => isNetIPCIDRString
  | .netLoopbackIP => isNetLoopbackIP
  | .netMulticastIP => isNetMulticastIP
  | .netInterfaceLocalMulticastIP => isNetInterfaceLocalMulticastIP
  | .netLinkLocalMulticastIP => isNetLinkLocalMulticastIP
  | .netLinkLocalUnicastIP => isNetLinkLocalUnicastIP
  | .netGlobalUnicastIP => isNetGlobalUnicastIP
  | .netUnspecifiedIP => isNetUnspecifiedIP

end Kue
