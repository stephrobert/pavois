package engine

import "testing"

// A docker target is a container by construction: no probe, no network, no ambiguity.
func TestIsContainerDockerTransport(t *testing.T) {
	yes, kind := IsContainer(Options{Target: "some-container"})
	if !yes {
		t.Fatal("a docker:// target must be reported as a container")
	}
	if kind != "docker" {
		t.Fatalf("kind = %q, want docker", kind)
	}
}

// The machine running the tests is not a container (CI runs on a VM, developers on metal). The
// point of this case is the DIRECTION of the guard's failure: when the probe cannot answer, it
// must say "not a container" and let the scan through, never invent a refusal. A guard that
// wrongly fires here would refuse every legitimate local scan.
func TestIsContainerLocalIsNotRefused(t *testing.T) {
	if yes, kind := IsContainer(Options{Target: "local"}); yes {
		t.Fatalf("local target reported as a %s container; a false positive here blocks every local scan", kind)
	}
}

// An unreachable ssh target cannot answer the probe. The guard must not turn that into a refusal:
// the scan itself will fail later with a connection error, which is the honest message.
func TestIsContainerUnreachableSSHDoesNotRefuse(t *testing.T) {
	// 203.0.113.0/24 is TEST-NET-3 (RFC 5737): guaranteed not to route anywhere.
	if yes, _ := IsContainer(Options{Target: "nobody@203.0.113.1"}); yes {
		t.Fatal("an unreachable host must not be reported as a container")
	}
}
