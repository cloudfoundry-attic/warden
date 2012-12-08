package pool

import (
	. "launchpad.net/gocheck"
)

type PortPoolSuite struct{}

var _ = Suite(&PortPoolSuite{})

func (s *PortPoolSuite) TestAcquire(c *C) {
	var x uint16
	var ok bool

	p := NewPortPool(61000, 256)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint16(61000))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint16(61001))
	c.Check(ok, Equals, true)
}

func (s *PortPoolSuite) TestAcquireAll(c *C) {
	p := NewPortPool(61000, 256)

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}
