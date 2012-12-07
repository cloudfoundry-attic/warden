package pool

import (
	. "launchpad.net/gocheck"
)

type PoolSuite struct{}

var _ = Suite(&PoolSuite{})

func (s *PoolSuite) TestAcquire(c *C) {
	var x uint
	var ok bool

	p := &Port{StartPort: 61000, Size: 256}

	x, ok = p.Acquire()
	c.Check(x, Equals, uint(61000))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint(61001))
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestAcquireAll(c *C) {
	p := &Port{StartPort: 61000, Size: 256}

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}

func (s *PoolSuite) TestRelease(c *C) {
	var x uint
	var ok bool

	p := &Port{StartPort: 61000, Size: 1}

	x, ok = p.Acquire()
	c.Check(x, Equals, uint(61000))
	c.Check(ok, Equals, true)

	_, ok = p.Acquire()
	c.Check(ok, Equals, false)

	p.Release(x)

	x, ok = p.Acquire()
	c.Check(x, Equals, uint(61000))
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestRemove(c *C) {
	p := &Port{StartPort: 61000, Size: 2}

	p.Remove(uint(61000))

	x, ok := p.Acquire()
	c.Check(x, Equals, uint(61001))
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestInit(c *C) {
	p := &Port{}

	// Acquire to trigger init
	_, _ = p.Acquire()

	c.Check(p.StartPort, Not(Equals), 0)
	c.Check(p.Size, Not(Equals), 0)
}
