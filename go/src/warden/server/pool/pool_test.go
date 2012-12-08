package pool

import (
	. "launchpad.net/gocheck"
)

type poolableInt int

func (x poolableInt) Next() Poolable {
	return poolableInt(x + 1)
}

func (x poolableInt) Equals(y Poolable) bool {
	return x == y.(poolableInt)
}

type PoolSuite struct{}

var _ = Suite(&PoolSuite{})

func (s *PoolSuite) TestAcquire(c *C) {
	var x Poolable
	var ok bool

	p := NewPool(poolableInt(0), 256)

	x, ok = p.Acquire()
	c.Check(x.(poolableInt), Equals, poolableInt(0))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x.(poolableInt), Equals, poolableInt(1))
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestAcquireAll(c *C) {
	p := NewPool(poolableInt(0), 256)

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}

func (s *PoolSuite) TestRelease(c *C) {
	var x Poolable
	var ok bool

	p := NewPool(poolableInt(0), 1)

	x, ok = p.Acquire()
	c.Check(x.(poolableInt), Equals, poolableInt(0))
	c.Check(ok, Equals, true)

	_, ok = p.Acquire()
	c.Check(ok, Equals, false)

	p.Release(x)

	x, ok = p.Acquire()
	c.Check(x.(poolableInt), Equals, poolableInt(0))
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestRemove(c *C) {
	p := NewPool(poolableInt(0), 2)

	p.Remove(poolableInt(0))

	x, ok := p.Acquire()
	c.Check(x.(poolableInt), Equals, poolableInt(1))
	c.Check(ok, Equals, true)
}
