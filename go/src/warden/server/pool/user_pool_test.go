package pool

import (
	. "launchpad.net/gocheck"
)

type UserPoolSuite struct{}

var _ = Suite(&UserPoolSuite{})

func (s *UserPoolSuite) TestAcquire(c *C) {
	var x uint16
	var ok bool

	p := NewUserPool(10000, 256)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint16(10000))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint16(10001))
	c.Check(ok, Equals, true)
}

func (s *UserPoolSuite) TestAcquireAll(c *C) {
	p := NewUserPool(10000, 256)

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}
