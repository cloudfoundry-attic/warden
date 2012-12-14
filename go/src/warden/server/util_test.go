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
