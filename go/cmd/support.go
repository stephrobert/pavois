package cmd

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strings"

	"github.com/spf13/cobra"

	"pavois/internal/corpus"
	"pavois/internal/engine"
)

// support turns "it did not work" into a bug report a maintainer can act on, without asking the
// user to find the repository, guess which facts matter, or retype them.
//
// # WHAT IT DOES NOT DO, and this is the design rather than a limitation
//
// It holds no token and posts nothing. It prints a report and a pre-filled URL; the human reads
// the body and clicks submit. The last gate is a person, which is the only acceptable arrangement
// for a tool that runs on machines it does not own.
//
// # WHAT GOES IN
//
// The facts `pavois doctor` already computes, and one of them decides half the diagnoses: whether
// the rule corpus came from INSIDE the binary or from the disk. That word separates a user running
// a release from a contributor in a checkout, and it is the class of defect v0.1.0, v0.1.1 and
// v0.1.2 each shipped, where a downloaded binary answered "this binary embeds none and none is on
// disk". The inventory is READ FROM doctor's own table (embeddedAssets), never re-implemented: a
// report whose numbers disagreed with doctor would send a maintainer looking in the wrong place.
//
// # WHAT NEVER GOES IN
//
// Host names, addresses, user names, key paths, environment, and above all not a scan report. A
// pavois report is the map of a real machine: accounts, services, file paths, addresses. The
// command a user ran and the message they got ARE needed, and both carry the target, so they are
// rewritten rather than dropped (see redact).
var supportCmd = &cobra.Command{
	Use:   "support",
	Short: "Prepare a bug report: the environment facts that matter, with the machine's identity removed",
	Args:  cobra.NoArgs,
	RunE:  runSupport,
}

var (
	supFailedCmd string
	supError     string
	supOpen      bool
)

// The one repository this binary belongs to.
//
// dsoxlab, which this command borrows its shape from, must never hardcode this: it serves several
// catalogues and only the CLI knows which one is open. Pavois has exactly one upstream, and a
// downloaded binary has no git remote to read, so a constant is the honest answer rather than a
// lookup that would fail for the user who most needs the command.
const issuesURL = "https://github.com/stephrobert/pavois/issues/new"

// Past this many characters the pre-filled URL stops being opened.
//
// The API accepts a 65536 character body, but the URL breaks far below that: percent-encoding
// triples every byte and the server answers 414 Request-URI too large without opening anything.
// That is the known `gh --web` defect (cli/cli#1575). 8000 leaves room under the usual 8 KiB
// server limit without having to measure GitHub's.
const urlLimit = 8000

func init() {
	supportCmd.Flags().StringVar(&supFailedCmd, "command", "",
		"the pavois command that failed (arguments are replaced by placeholders)")
	supportCmd.Flags().StringVar(&supError, "error", "",
		"the message pavois printed (addresses, targets and paths are removed)")
	supportCmd.Flags().BoolVar(&supOpen, "open", false,
		"open the pre-filled issue in a browser instead of only printing the URL")
	rootCmd.AddCommand(supportCmd)
}

// ---------------------------------------------------------------- redaction

var (
	// A target as pavois accepts it, and as its own error messages quote it back.
	reTarget = regexp.MustCompile(`\b[A-Za-z_][\w.-]*@[\w.:-]+`)
	reIPv4   = regexp.MustCompile(`\b(?:\d{1,3}\.){3}\d{1,3}\b`)
	// Deliberately loose: it collects what COULD be an address, and net.ParseIP decides. Form does
	// not settle this question, a parser does. `12:34:56` and `15:04:05` are shaped exactly like an
	// address and are an elapsed time and a timestamp; a rule that ate them would empty the report,
	// which is the failure nobody notices because the issue still opens and still looks plausible.
	reIPv6Cand = regexp.MustCompile(`[0-9a-fA-F]{0,4}(?::[0-9a-fA-F]{0,4}){2,}`)
	reHome     = regexp.MustCompile(`/home/[^/\s:,'"]+`)
	reKey      = regexp.MustCompile(`(--key[= ])(\S+)`)
	reIdent    = regexp.MustCompile(`\b(?:id_ed25519|id_rsa|id_ecdsa)\S*`)
)

func isWordByte(b byte) bool {
	return b == '_' || (b >= '0' && b <= '9') || (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z')
}

// redactIPv6 replaces the candidates net.ParseIP recognises, and only those.
//
// A candidate that starts or ends inside a word is refused before parsing: `Inspec::Exceptions` is
// a Ruby constant and CINC prints it constantly, yet its `ec::E` slice parses as an address.
func redactIPv6(s string) string {
	var b strings.Builder
	last := 0
	for _, m := range reIPv6Cand.FindAllStringIndex(s, -1) {
		start, end := m[0], m[1]
		if start > 0 && isWordByte(s[start-1]) {
			continue
		}
		if end < len(s) && isWordByte(s[end]) {
			continue
		}
		if ip := net.ParseIP(s[start:end]); ip == nil || ip.To4() != nil {
			continue
		}
		b.WriteString(s[last:start])
		b.WriteString("<ip>")
		last = end
	}
	b.WriteString(s[last:])
	return b.String()
}

// redact removes what identifies a machine and keeps what explains a failure.
//
// Order matters: --key takes its argument before the generic path rules see it, and the host name
// is substituted last so it cannot re-introduce a fragment of an address already replaced.
func redact(s string) string {
	s = reKey.ReplaceAllString(s, "$1<key>")
	s = reTarget.ReplaceAllString(s, "<target>")
	s = reIPv4.ReplaceAllString(s, "<ip>")
	s = redactIPv6(s)
	s = reIdent.ReplaceAllString(s, "<key>")
	s = reHome.ReplaceAllString(s, "~")
	if h, err := os.Hostname(); err == nil && len(h) > 2 {
		s = strings.ReplaceAll(s, h, "<host>")
	}
	return s
}

// ---------------------------------------------------------------- the facts

// corpusOrigin answers the one question that separates a user from a contributor.
func corpusOrigin(root string) string {
	rb, _ := filepath.Glob(filepath.Join(root, "profiles", "linux", "*", "controls", "*.rb"))
	switch {
	case len(rb) > 0:
		ctrls, oses := 0, map[string]bool{}
		for _, f := range rb {
			b, err := os.ReadFile(f) //nolint:gosec // path from our own glob under the repo root
			if err != nil {
				continue
			}
			ctrls += len(controlDecl.FindAll(b, -1))
			oses[filepath.Base(filepath.Dir(filepath.Dir(f)))] = true
		}
		return fmt.Sprintf("%d controls / %d profiles, RENDERED ON DISK (a checkout)", ctrls, len(oses))
	case corpus.Available():
		return fmt.Sprintf("%d controls / %d profiles, EMBEDDED in this binary",
			corpus.Controls(), len(corpus.Names()))
	default:
		return "NOT AVAILABLE: neither embedded nor on disk"
	}
}

func engineFact() string {
	bin := engine.NativeBin()
	if bin == "" {
		if _, err := exec.LookPath("docker"); err == nil {
			return "none native, docker present"
		}
		return "none"
	}
	// The VERSION, never the path: a path can carry a user name or a site's layout.
	out, err := exec.Command(bin, "version").Output() //nolint:gosec // bin comes from engine.NativeBin
	v := "version unknown"
	if err == nil {
		if f := strings.Fields(strings.TrimSpace(string(out))); len(f) > 0 {
			v = f[len(f)-1]
		}
	}
	return "native, cinc-auditor " + v
}

// report is the body, and it is meant to be READ by the person who submits it.
func report(root string) string {
	var b strings.Builder
	// The first thing a maintainer reads, and the only thing this command cannot compute. Leaving
	// the slot visible is what turns an environment dump into a bug report.
	b.WriteString("### What happened\n\n" +
		"_Replace this line: what you expected, what you got, and how to reproduce it._\n\n")
	b.WriteString("### Environment\n\n```\n")
	fmt.Fprintf(&b, "pavois        %s (%s/%s)\n", version, runtime.GOOS, runtime.GOARCH)
	fmt.Fprintf(&b, "engine        %s\n", engineFact())
	fmt.Fprintf(&b, "corpus        %s\n", corpusOrigin(root))
	var assets []string
	for _, a := range embeddedAssets(root) {
		d, err := a.count()
		if err != nil {
			d = "MISSING: " + err.Error()
		}
		assets = append(assets, fmt.Sprintf("%s %s", a.label, d))
	}
	fmt.Fprintf(&b, "assets        %s\n", strings.Join(assets, "\n              "))
	if name, rel := engine.Detect(engine.Options{Target: "local"}); name != "" {
		fmt.Fprintf(&b, "OS            %s %s\n", name, rel)
	} else {
		fmt.Fprintf(&b, "OS            not detected (no native engine, or it could not answer)\n")
	}
	b.WriteString("```\n")

	if supFailedCmd != "" {
		fmt.Fprintf(&b, "\n### Command\n\n```\n%s\n```\n", redact(supFailedCmd))
	}
	if supError != "" {
		fmt.Fprintf(&b, "\n### What pavois printed\n\n```\n%s\n```\n", redact(supError))
	}
	b.WriteString("\n### What is missing from this report, on purpose\n\n" +
		"It carries no scan result. A pavois report names real accounts, services, paths and " +
		"addresses, so it is never attached automatically. If you can share one, read it first.\n")
	return b.String()
}

// ---------------------------------------------------------------- the command

func runSupport(cmd *cobra.Command, _ []string) error {
	out := cmd.OutOrStdout()
	body := report(findRoot())

	_, _ = fmt.Fprintln(out, "pavois support: this is what would be sent, and nothing else.")
	_, _ = fmt.Fprintln(out)
	_, _ = fmt.Fprintln(out, body)

	link, dropped := prefilled(body)
	if dropped != "" {
		_, _ = fmt.Fprintf(out, "note: %s\n\n", dropped)
	}
	_, _ = fmt.Fprintln(out, "Open this to submit it (nothing has been sent):")
	_, _ = fmt.Fprintln(out, "  "+link)
	if supOpen {
		if err := openInBrowser(link); err != nil {
			_, _ = fmt.Fprintf(out, "\ncould not open a browser (%v): use the URL above\n", err)
		}
	}
	return nil
}

// prefilled builds the URL and says what it had to leave out, rather than silently truncating.
func prefilled(body string) (link, dropped string) {
	build := func(s string) string {
		// No `title=`: an empty parameter is noise, and a title this command invented would be
		// worse than the one sentence the reporter has to write for themselves.
		q := url.Values{}
		q.Set("body", s)
		return issuesURL + "?" + q.Encode()
	}
	if u := build(body); len(u) <= urlLimit {
		return u, ""
	}
	// Degrade in one visible step: keep the Environment block, which is the half a maintainer
	// cannot reconstruct, and drop what the reporter can paste by hand.
	if i := strings.Index(body, "\n### Command"); i > 0 {
		short := body[:i] + "\n(the command and the message were too long for a pre-filled URL; " +
			"paste them into the issue)\n"
		if u := build(short); len(u) <= urlLimit {
			return u, "the command and the message did not fit in the URL: paste them yourself"
		}
	}
	return issuesURL, "the report did not fit in a URL: paste the text above into the empty form"
}

func openInBrowser(link string) error {
	bin := "xdg-open"
	if runtime.GOOS == "darwin" {
		bin = "open"
	}
	if _, err := exec.LookPath(bin); err != nil {
		return fmt.Errorf("%s not found", bin)
	}
	return exec.Command(bin, link).Start() //nolint:gosec // link is built from a constant + encoding
}
