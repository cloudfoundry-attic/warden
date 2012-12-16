package server

import (
	. "launchpad.net/gocheck"
)

type IdSuite struct{}

var _ = Suite(&IdSuite{})

func (s *IdSuite) TestLength(c *C) {
	for i := 0; i < 100; i++ {
		s := NextId()
		c.Check(len(s), Equals, 11)
	}
}

type MountPointSuite struct{}

var _ = Suite(&MountPointSuite{})

func (s *MountPointSuite) TestFindMountPoint(c *C) {
	var p string

	p = FindMountPoint("/")
	c.Check(p, Equals, "/")

	p = FindMountPoint("/../..")
	c.Check(p, Equals, "/")

	p = FindMountPoint("/proc/1")
	c.Check(p, Equals, "/proc")

	p = FindMountPoint("/proc/1/..")
	c.Check(p, Equals, "/proc")

	p = FindMountPoint("/proc/1/../..")
	c.Check(p, Equals, "/")
}
