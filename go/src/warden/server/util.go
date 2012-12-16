package server

import (
	"os"
	"path"
	"strconv"
	"syscall"
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

func FindMountPoint(p string) string {
	var f1, f2 os.FileInfo
	var s1, s2 *syscall.Stat_t
	var err error

	for p = path.Clean(p); p != "/"; p = path.Clean(p + "/..") {
		f1, err = os.Stat(p)
		if err != nil {
			panic(err)
		}

		f2, err = os.Stat(p + "/..")
		if err != nil {
			panic(err)
		}

		// Check if this crosses a device boundary
		s1 = f1.Sys().(*syscall.Stat_t)
		s2 = f2.Sys().(*syscall.Stat_t)
		if s1.Dev != s2.Dev {
			break
		}
	}

	return p
}
