package server

import (
	"strconv"
	"time"
)

// Seed Id with time since epoch in microseconds
var _Id = time.Now().UnixNano() / 1000

// Every container gets its own Id
func NextId() string {
	var s string
	var i uint

	_Id++

	// Explicit loop because we MUST have 11 characters.
	// This is required because we use the handle to name a network
	// interface for the container, this name has a 2 character prefix and
	// suffix, and has a maximum length of 15 characters (IFNAMSIZ).
	for i = 0; i < 11; i++ {
		s += strconv.FormatInt((_Id>>(55-(i+1)*5))&31, 32)
	}

	return s
}
