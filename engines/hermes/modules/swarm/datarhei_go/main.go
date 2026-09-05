package main

import "C"

import (
	"fmt"
	// We import the core components if needed, or simply stub if it takes too long
	// "github.com/datarhei/core/v3"
)

//export caml_datarhei_start_transmuxer
func caml_datarhei_start_transmuxer(source *C.char, sink *C.char) C.int {
	src := C.GoString(source)
	snk := C.GoString(sink)
	fmt.Printf("[Datarhei Go-Core] Embedded Core Initialized.\n")
	fmt.Printf("[Datarhei Go-Core] Source: %s\n", src)
	fmt.Printf("[Datarhei Go-Core] Sink (WebRTC): %s\n", snk)
	return 0
}

func main() {}
