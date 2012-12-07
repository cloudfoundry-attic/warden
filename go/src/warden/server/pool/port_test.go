package pool

import (
	. "launchpad.net/gocheck"
)

type PoolSuite struct{}

var _ = Suite(&PoolSuite{})

func (s *PoolSuite) TestAcquire(c *C) {
	p := &Port{StartPort: 61000, Size: 256}

	c.Check(*p.Acquire(), Equals, uint(61000))
	c.Check(*p.Acquire(), Equals, uint(61001))
}

func (s *PoolSuite) TestAcquireAll(c *C) {
	p := &Port{StartPort: 61000, Size: 256}

	for i := 0; i < 256; i++ {
		c.Check(p.Acquire(), Not(IsNil))
	}

	c.Check(p.Acquire(), IsNil)
}

func (s *PoolSuite) TestRelease(c *C) {
	var i1, i2 *uint

	p := &Port{StartPort: 61000, Size: 1}

	i1 = p.Acquire()
	c.Check(i1, Not(IsNil))

	i2 = p.Acquire()
	c.Check(i2, IsNil)

	p.Release(*i1)

	i2 = p.Acquire()
	c.Check(i2, Not(IsNil))
}

func (s *PoolSuite) TestRemove(c *C) {
	p := &Port{StartPort: 61000, Size: 2}

	p.Remove(61000)

	c.Check(*p.Acquire(), Equals, uint(61001))
}

func (s *PoolSuite) TestInit(c *C) {
	p := &Port{}

	// Acquire to trigger init
	_ = p.Acquire()

	c.Check(p.StartPort, Not(Equals), 0)
	c.Check(p.Size, Not(Equals), 0)
}
