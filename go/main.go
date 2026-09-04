// pavois: a compliance scanner (CINC/InSpec) aware of the effective config.
// Go port of the Python CLI, reusing the scankit libs (presentation, findings,
// scoring) pitstop-style.
package main

import "pavois/cmd"

func main() { cmd.Execute() }
