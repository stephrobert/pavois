package engine

import (
	"strings"
	"testing"
)

// The arguments below are not decoration: without the waiver file the project's own accepted
// risks are graded as plain failures, and without the standard input every merged rule falls back
// to `_default`, so `--standard cis` grades against the strictest threshold instead of the CIS
// one. Both were passed by the native branch only, which is the defect this covers (#204).
func TestAuditArgsCarriesWaiverAndStandard(t *testing.T) {
	cases := []struct {
		name       string
		prof       string
		waiver     string
		standard   string
		wantWaiver string // "" = no --waiver-file expected
		wantStd    string
	}{
		{
			name:       "native paths: the waiver is named by the profile directory",
			prof:       "/opt/pavois/profiles/linux/debian12",
			waiver:     "/opt/pavois/profiles/linux/debian12/waivers.yml",
			standard:   "cis",
			wantWaiver: "/opt/pavois/profiles/linux/debian12/waivers.yml",
			wantStd:    "cis",
		},
		{
			name:       "docker paths: the engine reads the MOUNTED profile, not the host one",
			prof:       "/profile",
			waiver:     "/opt/pavois/profiles/linux/debian12/waivers.yml", // exists on the host
			standard:   "bp28",
			wantWaiver: "/profile/waivers.yml",
			wantStd:    "bp28",
		},
		{
			name:     "a profile with no waivers.yml gets no --waiver-file",
			prof:     "/profile",
			waiver:   "",
			standard: "cis",
			wantStd:  "cis",
		},
		{
			name:       "no standard means the strictest, never an absent input",
			prof:       "/profile",
			waiver:     "/host/waivers.yml",
			standard:   "",
			wantWaiver: "/profile/waivers.yml",
			wantStd:    "_default",
		},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := strings.Join(auditArgs(c.prof, c.waiver, c.standard), " ")

			if c.wantWaiver == "" {
				if strings.Contains(got, "--waiver-file") {
					t.Errorf("no waivers.yml, yet a waiver file was passed: %q", got)
				}
			} else if !strings.Contains(got, "--waiver-file "+c.wantWaiver) {
				t.Errorf("waiver file missing or wrong\n got: %q\nwant it to contain: --waiver-file %s",
					got, c.wantWaiver)
			}

			if !strings.Contains(got, "--input pavois_standard="+c.wantStd) {
				t.Errorf("standard input missing or wrong\n got: %q\nwant it to contain: --input pavois_standard=%s",
					got, c.wantStd)
			}
		})
	}
}
