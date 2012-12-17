package pool

import (
	"encoding/json"
	. "launchpad.net/gocheck"
)

type PortPoolSuite struct{}

var _ = Suite(&PortPoolSuite{})

func (s *PortPoolSuite) TestAcquire(c *C) {
	var x Port
	var ok bool

	p := NewPortPool(61000, 256)

	x, ok = p.Acquire()
	c.Check(x, Equals, Port(61000))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x, Equals, Port(61001))
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

func (s *PortPoolSuite) TestJson(c *C) {
	var i, j Port
	var ok bool

	p := NewPortPool(61000, 1)

	i, ok = p.Acquire()
	c.Check(ok, Equals, true)

	// Marshal
	d, err := json.Marshal(i)
	c.Check(err, IsNil)

	// Unmarshal
	err = json.Unmarshal(d, &j)
	c.Check(err, IsNil)

	// Assert equality
	c.Check(j, DeepEquals, i)
}
