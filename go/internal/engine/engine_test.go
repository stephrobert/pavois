package engine

import "testing"

func TestTruncShort(t *testing.T) {
	cases := []struct {
		name, in string
		n        int
		want     string
	}{
		{"shorter than limit is trimmed only", "  hello  ", 20, "hello"},
		{"exactly at limit", "abcde", 5, "abcde"},
		{"longer is truncated with ellipsis", "abcdefgh", 5, "abcd…"},
		{"empty", "   ", 5, ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := truncShort(c.in, c.n); got != c.want {
				t.Errorf("truncShort(%q,%d) = %q, want %q", c.in, c.n, got, c.want)
			}
		})
	}
}
