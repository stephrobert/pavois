package cmd

import (
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"

	"pavois/internal/audit"
)

// `pavois oscal` publishes the Pavois baseline as OSCAL (the NIST format CIS/NIST adopt): a
// Catalog (one control per neutral id, with the EFFECTIVE-CONFIG check + per-OS CIS/STIG numbers
// + norm-reference links) and per-OS Profiles that import it. This makes the source of truth a
// machine-readable STANDARD any OSCAL/GRC tool (ciso-assistant) can consume: uniquely an
// effective-config one. The publication face of the reference, alongside `norms` and `rules`.
const (
	oscalNS  = "https://pavois.dev/ns/oscal"
	oscalVer = "1.1.2"
)

// baselineMeta is the citable identity, read from docs/reference/baseline.yml (single source of the
// version/name/date). Keeps the published standard governed in one place rather than hardcoded.
type baselineMeta struct {
	Name        string `yaml:"name"`
	Version     string `yaml:"version"`
	Released    string `yaml:"released"`
	License     string `yaml:"license"`
	Authority   string `yaml:"authority"`
	Description string `yaml:"description"`
}

func readBaseline(root string) baselineMeta {
	m := baselineMeta{Name: "Pavois: Effective-Configuration Hardening Baseline", Version: "0.0.0", Released: "1970-01-01"}
	if b, err := os.ReadFile(filepath.Join(root, "docs", "reference", "baseline.yml")); err == nil {
		_ = yaml.Unmarshal(b, &m)
	}
	return m
}

var oscalOut string

var oscalCmd = &cobra.Command{
	Use:   "oscal",
	Short: "Publish the Pavois baseline as OSCAL (catalog + per-OS profiles)",
	Long: "Emit the Pavois Effective-Configuration Hardening Baseline as an OSCAL 1.1.2 catalog\n" +
		"(one control per neutral id, grouped by domain, carrying method=<evidence_type>, the\n" +
		"real check, per-OS CIS/STIG numbers and norm links) plus per-OS profiles. With no --out\n" +
		"the catalog prints to stdout; --out DIR writes the catalog + profiles/.",
	RunE: runOscal,
}

func init() {
	oscalCmd.Flags().StringVar(&oscalOut, "out", "", "write catalog + profiles to this directory (default: stdout)")
	rootCmd.AddCommand(oscalCmd)
}

type oProp struct {
	Name  string `json:"name"`
	Value string `json:"value"`
	NS    string `json:"ns,omitempty"`
	Class string `json:"class,omitempty"`
}
type oLink struct {
	Href string `json:"href"`
	Rel  string `json:"rel,omitempty"`
}
type oPart struct {
	ID    string `json:"id"`
	Name  string `json:"name"`
	Prose string `json:"prose"`
}
type oControl struct {
	ID    string  `json:"id"`
	Title string  `json:"title"`
	Props []oProp `json:"props,omitempty"`
	Links []oLink `json:"links,omitempty"`
	Parts []oPart `json:"parts,omitempty"`
}
type oGroup struct {
	ID       string     `json:"id"`
	Title    string     `json:"title"`
	Controls []oControl `json:"controls"`
}
type oMeta struct {
	Title        string `json:"title"`
	LastModified string `json:"last-modified"`
	Version      string `json:"version"`
	OscalVersion string `json:"oscal-version"`
	Remarks      string `json:"remarks,omitempty"`
}
type oCatalog struct {
	Catalog struct {
		UUID     string   `json:"uuid"`
		Metadata oMeta    `json:"metadata"`
		Groups   []oGroup `json:"groups"`
	} `json:"catalog"`
}
type oProfile struct {
	Profile struct {
		UUID     string `json:"uuid"`
		Metadata oMeta  `json:"metadata"`
		Imports  []struct {
			Href            string `json:"href"`
			IncludeControls []struct {
				WithIds []string `json:"with-ids"`
			} `json:"include-controls"`
		} `json:"imports"`
	} `json:"profile"`
}

type oRule struct {
	Title    string         `yaml:"title"`
	Domain   string         `yaml:"domain"`
	Severity string         `yaml:"severity"`
	Socle    string         `yaml:"socle"`
	Evidence string         `yaml:"evidence_type"`
	Reboot   string         `yaml:"reboot_survivable"`
	Check    []string       `yaml:"check"`
	Norms    map[string]any `yaml:"norms"`
}

// provesFor derives what a passing check establishes from its evidence type: the qualified
// verdict [running, persistent, reboot-survivable] as yes/unknown/na. Matches the fiche PROVES
// table and the engine's grade policy (single source: audit.Proves).
func provesFor(method string) [3]string { return audit.Proves(method) }

var urlNS = []byte{0x6b, 0xa7, 0xb8, 0x11, 0x9d, 0xad, 0x11, 0xd1, 0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8}

// uuidName derives a deterministic, syntactically valid RFC 4122 UUID from a name,
// hashing with SHA-256 (sha1 is weak: G401/G505). OSCAL only requires a well-formed
// UUID for document identifiers, not a true name-based v5, so we keep the version/variant
// bits well-formed and use the stronger digest. Output is stable across runs for a name.
func uuidName(name string) string {
	h := sha256.New()
	h.Write(urlNS)
	h.Write([]byte("https://pavois.dev/baseline:" + name))
	b := h.Sum(nil)[:16]
	b[6] = (b[6] & 0x0f) | 0x50
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func flat(v any) []string {
	switch x := v.(type) {
	case nil:
		return nil
	case string:
		return []string{x}
	case []any:
		out := make([]string, 0, len(x))
		for _, e := range x {
			out = append(out, fmt.Sprint(e))
		}
		return out
	default:
		return []string{fmt.Sprint(x)}
	}
}

func runOscal(_ *cobra.Command, _ []string) error {
	root := findRoot()
	dir := filepath.Join(root, "docs", "reference", "pavois-content")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return fmt.Errorf("read reference: %w", err)
	}
	var oses []string
	data := map[string]map[string]oRule{}
	for _, f := range entries {
		if filepath.Ext(f.Name()) != ".yml" {
			continue
		}
		osn := strings.TrimSuffix(f.Name(), ".yml")
		b, err := os.ReadFile(filepath.Join(dir, f.Name()))
		if err != nil {
			return err
		}
		var doc struct {
			Rules map[string]oRule `yaml:"rules"`
		}
		if err := yaml.Unmarshal(b, &doc); err != nil {
			return fmt.Errorf("parse %s: %w", f.Name(), err)
		}
		oses = append(oses, osn)
		data[osn] = doc.Rules
	}
	sort.Strings(oses)

	idset := map[string]bool{}
	for _, osn := range oses {
		for id := range data[osn] {
			idset[id] = true
		}
	}
	ids := make([]string, 0, len(idset))
	for id := range idset {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	first := func(id string) oRule {
		for _, osn := range oses {
			if r, ok := data[osn][id]; ok {
				return r
			}
		}
		return oRule{}
	}

	byDomain := map[string][]oControl{}
	for _, id := range ids {
		e := first(id)
		// method = the control's real evidence type (effective-runtime / persistent-config /
		// inventory-state / filesystem-state / manual / behavioral), not a blanket claim.
		method := e.Evidence
		if method == "" {
			method = "unclassified"
		}
		props := []oProp{{Name: "method", NS: oscalNS, Value: method}}
		// Qualified verdict: what a passing check proves, derived from the evidence type
		// (yes proven / unknown not-measured / na). Mirrors the site fiche's "A pass proves".
		pr := provesFor(method)
		// reboot_survivable is the authoritative persistence axis: a folded check (e.g. sysctl
		// asserting /etc/sysctl.d) proves on-disk + reboot-survivable even when the method is a
		// runtime read. Override the evidence-derived persistence row accordingly.
		if e.Reboot == "yes" {
			pr[1], pr[2] = "yes", "yes"
		} else if e.Reboot == "no" && pr[2] != "no" {
			pr[2] = "no"
		}
		props = append(props,
			oProp{Name: "proves-running", NS: oscalNS, Value: pr[0]},
			oProp{Name: "proves-persistent", NS: oscalNS, Value: pr[1]},
			oProp{Name: "proves-reboot-survivable", NS: oscalNS, Value: pr[2]},
		)
		if e.Socle != "" {
			props = append(props, oProp{Name: "socle", NS: oscalNS, Value: e.Socle})
		}
		if e.Severity != "" {
			props = append(props, oProp{Name: "severity", Value: e.Severity})
		}
		if len(e.Check) > 0 {
			props = append(props, oProp{Name: "check", NS: oscalNS, Value: strings.Join(e.Check, "\n")})
		}
		for _, nm := range []string{"cis", "stig"} {
			for _, osn := range oses {
				if r, ok := data[osn][id]; ok && r.Norms != nil {
					for _, v := range flat(r.Norms[nm]) {
						props = append(props, oProp{Name: nm, Class: osn, Value: v})
					}
				}
			}
		}
		var links []oLink
		for _, nm := range []string{"bp28", "nist", "pci-dss"} {
			if e.Norms != nil {
				for _, v := range flat(e.Norms[nm]) {
					links = append(links, oLink{Href: "#" + nm + "-" + strings.ReplaceAll(v, " ", "_"), Rel: "reference"})
				}
			}
		}
		title := e.Title
		if title == "" {
			title = id
		}
		c := oControl{ID: id, Title: title, Props: props, Links: links,
			Parts: []oPart{{ID: id + "_smt", Name: "statement", Prose: title}}}
		dom := e.Domain
		if dom == "" {
			dom = "Other"
		}
		byDomain[dom] = append(byDomain[dom], c)
	}
	doms := make([]string, 0, len(byDomain))
	for d := range byDomain {
		doms = append(doms, d)
	}
	sort.Strings(doms)
	bl := readBaseline(root)
	oscalTS := bl.Released + "T00:00:00Z" // stamped from the release date: deterministic, reproducible
	var cat oCatalog
	cat.Catalog.UUID = uuidName("catalog")
	cat.Catalog.Metadata = oMeta{
		Title: bl.Name, LastModified: oscalTS, Version: bl.Version, OscalVersion: oscalVer,
		Remarks: strings.TrimSpace(bl.Description),
	}
	for i, d := range doms {
		cat.Catalog.Groups = append(cat.Catalog.Groups, oGroup{ID: fmt.Sprintf("d-%d", i), Title: d, Controls: byDomain[d]})
	}

	if oscalOut == "" {
		b, _ := json.MarshalIndent(cat, "", "  ")
		fmt.Println(string(b))
		return nil
	}
	if err := os.MkdirAll(filepath.Join(oscalOut, "profiles"), 0o750); err != nil {
		return err
	}
	cb, _ := json.MarshalIndent(cat, "", "  ")
	if err := os.WriteFile(filepath.Join(oscalOut, "pavois-catalog.json"), cb, 0o600); err != nil {
		return err
	}
	for _, osn := range oses {
		pids := make([]string, 0, len(data[osn]))
		for id := range data[osn] {
			pids = append(pids, id)
		}
		sort.Strings(pids)
		var p oProfile
		p.Profile.UUID = uuidName("profile:" + osn)
		p.Profile.Metadata = oMeta{Title: "Pavois baseline: " + osn, LastModified: oscalTS, Version: bl.Version, OscalVersion: oscalVer}
		p.Profile.Imports = append(p.Profile.Imports, struct {
			Href            string `json:"href"`
			IncludeControls []struct {
				WithIds []string `json:"with-ids"`
			} `json:"include-controls"`
		}{Href: "../pavois-catalog.json", IncludeControls: []struct {
			WithIds []string `json:"with-ids"`
		}{{WithIds: pids}}})
		pb, _ := json.MarshalIndent(p, "", "  ")
		if err := os.WriteFile(filepath.Join(oscalOut, "profiles", "pavois-"+osn+".json"), pb, 0o600); err != nil {
			return err
		}
	}
	_, _ = fmt.Fprintf(os.Stderr, "pavois: OSCAL catalog (%d controls) + %d profiles -> %s\n", len(ids), len(oses), oscalOut)
	return nil
}
