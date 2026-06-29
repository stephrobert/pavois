package render

import (
	"encoding/json"
	"strings"
	"testing"

	"pavois/internal/audit"
)

func TestSeverity(t *testing.T) {
	tests := []struct {
		impact float64
		want   string
	}{
		{1.0, "critique"},
		{0.9, "critique"},
		{0.89, "haute"},
		{0.7, "haute"},
		{0.69, "moyenne"},
		{0.4, "moyenne"},
		{0.39, "basse"},
		{0.0, "basse"},
	}
	for _, tc := range tests {
		if got := severity(tc.impact); got != tc.want {
			t.Errorf("severity(%g) = %q, want %q", tc.impact, got, tc.want)
		}
	}
}

// ctrlFromJSON builds an audit.Control through JSON so the anonymous Results struct
// can be populated — the same decoding path used on real InSpec reports.
func ctrlFromJSON(t *testing.T, raw string) audit.Control {
	t.Helper()
	var c audit.Control
	if err := json.Unmarshal([]byte(raw), &c); err != nil {
		t.Fatalf("unmarshal control: %v", err)
	}
	return c
}

func TestStatus(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{"no results is empty", `{"id":"x"}`, "empty"},
		{"any failed is failed", `{"id":"x","results":[{"status":"passed"},{"status":"failed"}]}`, "failed"},
		{"all skipped is skipped", `{"id":"x","results":[{"status":"skipped"},{"status":"skipped"}]}`, "skipped"},
		{"otherwise passed", `{"id":"x","results":[{"status":"passed"},{"status":"skipped"}]}`, "passed"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c := ctrlFromJSON(t, tc.raw)
			if got := status(c); got != tc.want {
				t.Errorf("status = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestDomain(t *testing.T) {
	tests := []struct {
		name string
		raw  string
		want string
	}{
		{"domain tag wins", `{"id":"ssh-x","tags":{"domain":"ssh"}}`, "ssh"},
		{"section tag fallback", `{"id":"ssh-x","tags":{"section":"5.2"}}`, "5.2"},
		{"id prefix fallback", `{"id":"svc-telnet-removed"}`, "svc"},
		{"prefix stops at digit", `{"id":"net4-foo"}`, "net"},
		{"empty prefix is Divers", `{"id":"-x"}`, "Divers"},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			c := ctrlFromJSON(t, tc.raw)
			if got := domain(c); got != tc.want {
				t.Errorf("domain = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestControlData(t *testing.T) {
	c := ctrlFromJSON(t, `{
		"id":"ssh-permitrootlogin",
		"title":"Disable root SSH login",
		"desc":"  root login over SSH must be off  ",
		"impact":0.7,
		"tags":{
			"domain":"ssh",
			"cis":"5.2.10",
			"bp28":"R31",
			"level_cis":"1",
			"level_bp28":"minimal",
			"evidence":"runtime",
			"reboot":"no"
		},
		"refs":[{"ref":"CCE-1234"},{"url":"https://example.test/x"}],
		"results":[{"status":"failed","code_desc":"check sshd -T","message":"  found yes  "}]
	}`)

	cd := controlData(c)

	if cd.ID != "ssh-permitrootlogin" {
		t.Errorf("ID = %q", cd.ID)
	}
	if cd.Title != "Disable root SSH login" {
		t.Errorf("Title = %q", cd.Title)
	}
	if cd.Desc != "root login over SSH must be off" {
		t.Errorf("Desc not trimmed: %q", cd.Desc)
	}
	if cd.Sev != "haute" {
		t.Errorf("Sev = %q, want haute (impact 0.7)", cd.Sev)
	}
	if cd.Status != "failed" {
		t.Errorf("Status = %q, want failed", cd.Status)
	}
	if cd.Domain != "ssh" {
		t.Errorf("Domain = %q", cd.Domain)
	}
	if cd.Norms["cis"] != "5.2.10" || cd.Norms["bp28"] != "R31" {
		t.Errorf("Norms = %v", cd.Norms)
	}
	if cd.Levels["cis"] != "1" || cd.Levels["bp28"] != "minimal" {
		t.Errorf("Levels = %v", cd.Levels)
	}
	if cd.Evidence != "runtime" || cd.Reboot != "no" {
		t.Errorf("Evidence=%q Reboot=%q", cd.Evidence, cd.Reboot)
	}
	if len(cd.Refs) != 2 || cd.Refs[0] != "CCE-1234" || cd.Refs[1] != "https://example.test/x" {
		t.Errorf("Refs = %v", cd.Refs)
	}
	if len(cd.Checks) != 1 || cd.Checks[0].Msg != "found yes" {
		t.Errorf("Checks = %+v (message should be trimmed)", cd.Checks)
	}
}

func TestControlDataTitleFallsBackToID(t *testing.T) {
	c := ctrlFromJSON(t, `{"id":"orphan-id"}`)
	if cd := controlData(c); cd.Title != "orphan-id" {
		t.Errorf("Title fallback = %q, want orphan-id", cd.Title)
	}
}

func TestItoa(t *testing.T) {
	tests := map[int]string{0: "0", 1: "1", 9: "9", 10: "10", 123: "123"}
	for in, want := range tests {
		if got := itoa(in); got != want {
			t.Errorf("itoa(%d) = %q, want %q", in, got, want)
		}
	}
}

func TestEscape(t *testing.T) {
	if got := e(`<a href="x">&'`); !strings.Contains(got, "&lt;") || strings.Contains(got, "<a") {
		t.Errorf("e() did not escape HTML: %q", got)
	}
}

// buildReport constructs an audit.Report through JSON for the HTML golden-ish test.
func buildReport(t *testing.T, raw string) *audit.Report {
	t.Helper()
	var r audit.Report
	if err := json.Unmarshal([]byte(raw), &r); err != nil {
		t.Fatalf("unmarshal report: %v", err)
	}
	return &r
}

func TestHTML(t *testing.T) {
	rep := buildReport(t, `{
		"platform":{"name":"debian","release":"12"},
		"profiles":[{
			"title":"Pavois Debian 12","version":"1.0",
			"controls":[
				{"id":"ssh-permitrootlogin","title":"Root SSH off","impact":0.9,
				 "tags":{"domain":"ssh","cis":"5.2.10","bp28":"R31"},
				 "results":[{"status":"failed","code_desc":"sshd -T"}]},
				{"id":"sysctl-aslr","title":"ASLR","impact":0.5,
				 "tags":{"domain":"kernel","cis":"1.5.3"},
				 "results":[{"status":"passed","code_desc":"sysctl"}]}
			]
		}]
	}`)

	out, nctrl, nnorm := HTML(rep, Meta{
		Machine: "host01", Transport: "ssh://", Timestamp: "2026-06-29T10:00:00Z", Engine: "cinc-auditor",
	})

	if nctrl != 2 {
		t.Errorf("nctrl = %d, want 2", nctrl)
	}
	// bp28 + cis are present; nist/pci/stig are not.
	if nnorm != 2 {
		t.Errorf("nnorm = %d, want 2 (bp28, cis)", nnorm)
	}

	for _, want := range []string{
		"<!DOCTYPE html>",
		"Pavois Debian 12",
		"host01",
		"ssh://",
		"cinc-auditor",
		"var CFDATA=",
		"var CFNORMS=",
		`debian 12`, // osStr from platform
	} {
		if !strings.Contains(out, want) {
			t.Errorf("HTML output missing %q", want)
		}
	}

	// The embedded JSON payload must escape </ so a control title can't break out of
	// the <script> block.
	if strings.Contains(out, "</script></script") {
		t.Error("payload not isolated from script tags")
	}

	// Norm dropdown reflects the present standards with counts.
	if !strings.Contains(out, "ANSSI BP-028 (1)") {
		t.Errorf("missing bp28 option with count:\n%s", out[:min(len(out), 4000)])
	}
	if !strings.Contains(out, "CIS (2)") {
		t.Error("missing CIS option with count 2")
	}
}

func TestHTMLEmptyPlatform(t *testing.T) {
	rep := buildReport(t, `{"profiles":[{"controls":[]}]}`)
	out, nctrl, nnorm := HTML(rep, Meta{})
	if nctrl != 0 || nnorm != 0 {
		t.Errorf("empty report: nctrl=%d nnorm=%d, want 0/0", nctrl, nnorm)
	}
	if !strings.Contains(out, "n/a") {
		t.Error("empty platform should render osStr as n/a")
	}
}
