package engine

import "testing"

// The tests run as an ordinary user, and that is the case the guard exists for: it must be able to
// tell "not root" apart from "could not tell", because only the first justifies refusing a scan.
func TestEffectiveUIDLocalIsKnown(t *testing.T) {
	uid, known := EffectiveUID(Options{Target: "local"})
	if !known {
		t.Fatal("the local uid must be determinable; without it the guard cannot fire at all")
	}
	if uid < 0 {
		t.Fatalf("uid = %d", uid)
	}
}

// Unreachable host: the probe cannot answer, so the guard must report "unknown" and let the scan
// proceed to fail with a connection error, which is the honest message. Reporting a confident
// non-root uid here would refuse scans for the wrong reason.
func TestEffectiveUIDUnreachableIsUnknown(t *testing.T) {
	// 203.0.113.0/24 is TEST-NET-3 (RFC 5737): guaranteed not to route.
	if _, known := EffectiveUID(Options{Target: "nobody@203.0.113.1"}); known {
		t.Fatal("an unreachable host must not yield a known uid")
	}
}
