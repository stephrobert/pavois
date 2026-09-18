package cmd

import (
	"strings"
	"testing"
)

// The redaction has to be proven in BOTH directions, and the second half is the one that gets
// skipped: a rule that removes too much empties the report without anybody noticing, because the
// issue still opens and still looks plausible. So every case below asserts what must disappear AND
// what must survive.
func TestRedact(t *testing.T) {
	cases := []struct {
		name string
		in   string
		gone []string // must not appear anywhere in the output
		kept []string // must survive untouched: the report is worthless without it
	}{
		{
			name: "a target as pavois quotes it back in its own error",
			in:   "error: could not reach or identify admin@10.0.4.12: no native CINC engine found",
			gone: []string{"admin@10.0.4.12", "admin", "10.0.4.12"},
			kept: []string{"could not reach or identify", "no native CINC engine found"},
		},
		{
			name: "a command line with a key path and a home directory",
			in:   "pavois scan ops@srv1.example.net --key /home/alice/.ssh/id_ed25519 --sudo",
			gone: []string{"ops@srv1.example.net", "alice", "id_ed25519", "srv1.example.net"},
			kept: []string{"pavois scan", "--key", "--sudo"},
		},
		{
			name: "an IPv6 address",
			in:   "connecting to 2001:0db8:85a3:0000:0000:8a2e:0370:7334 failed",
			gone: []string{"2001:0db8", "8a2e"},
			kept: []string{"connecting to", "failed"},
		},
		{
			name: "a bare home path outside any flag",
			in:   "reading /home/bob/reports/scan.json",
			gone: []string{"/home/bob", "bob"},
			kept: []string{"reading", "reports/scan.json"},
		},
		{
			// The shape of an address is not an address. These three lines cost nothing to keep and
			// everything to lose: an elapsed time, a timestamp and a Ruby constant CINC prints in
			// every stack trace. `net.ParseIP` is what tells them apart, not a regular expression.
			name: "a duration, a timestamp and a Ruby constant are not addresses",
			in: "elapsed 12:34:56, started 15:04:05 UTC\n" +
				"Inspec::Exceptions::ResourceFailed: sshd -T exited 255\n" +
				"but ::1 and fe80::1 are addresses",
			gone: []string{"::1 and", "fe80"},
			kept: []string{
				"elapsed 12:34:56", "started 15:04:05 UTC",
				"Inspec::Exceptions::ResourceFailed", "sshd -T exited 255",
			},
		},
		{
			// THE WITNESS. A report made of these lines carries no identity at all, and an
			// over-eager rule that mangled them would leave a maintainer with nothing to read.
			name: "text that identifies no machine must pass through untouched",
			in: "pavois v0.1.5 (linux/amd64)\n" +
				"engine native, cinc-auditor 7.1.7\n" +
				"corpus 5937 controls / 9 profiles, EMBEDDED in this binary\n" +
				"grade D, 33 failing, ratio 1:4, elapsed 12:34\n" +
				"see https://pavois.dev/en/installation/#engine",
			gone: []string{},
			kept: []string{
				"v0.1.5", "linux/amd64", "cinc-auditor 7.1.7",
				"5937 controls / 9 profiles", "EMBEDDED in this binary",
				"grade D, 33 failing, ratio 1:4, elapsed 12:34",
				"https://pavois.dev/en/installation/#engine",
			},
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := redact(c.in)
			for _, g := range c.gone {
				if strings.Contains(out, g) {
					t.Errorf("%q survived redaction\n  in:  %s\n  out: %s", g, c.in, out)
				}
			}
			for _, k := range c.kept {
				if !strings.Contains(out, k) {
					t.Errorf("%q was destroyed by redaction\n  in:  %s\n  out: %s", k, c.in, out)
				}
			}
		})
	}
}

// The URL has a hard ceiling that is not the API's: percent-encoding triples every byte and the
// server answers 414 without opening anything. What matters is that the command SAYS what it left
// out rather than silently truncating, so a reporter knows to paste the rest.
func TestPrefilledDegradesAndSaysSo(t *testing.T) {
	short := "### Environment\n\n```\npavois v0.1.5\n```\n"
	link, dropped := prefilled(short)
	if dropped != "" {
		t.Errorf("a short body should fit whole, got dropped=%q", dropped)
	}
	if len(link) > urlLimit {
		t.Errorf("a short body produced a %d character URL", len(link))
	}

	long := short + "\n### Command\n\n```\n" + strings.Repeat("pavois scan local --sudo ", 2000) + "\n```\n"
	link, dropped = prefilled(long)
	if dropped == "" {
		t.Error("an oversized body was accepted without a word: it would 414 in the browser")
	}
	if len(link) > urlLimit {
		t.Errorf("the degraded URL is still %d characters", len(link))
	}
	if !strings.HasPrefix(link, issuesURL) {
		t.Errorf("the degraded link stopped pointing at the issue form: %s", link)
	}
}
