package main

/*
#include <stdlib.h>
*/
import "C"

import "unsafe"

var engine = NewEngine()

// BeadsCall runs one JSON request and returns a JSON response the caller frees with BeadsFree.
//
//export BeadsCall
func BeadsCall(request *C.char) *C.char {
	out := engine.Call([]byte(C.GoString(request)))
	return C.CString(string(out))
}

// BeadsFree releases a string BeadsCall returned.
//
//export BeadsFree
func BeadsFree(p *C.char) { C.free(unsafe.Pointer(p)) }

func main() {}
