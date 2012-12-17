package pool

import (
	"encoding/json"
	. "launchpad.net/gocheck"
)

type NetworkPoolSuite struct{}

var _ = Suite(&NetworkPoolSuite{})

func (s *NetworkPoolSuite) TestAcquire(c *C) {
	var ip IP
	var ok bool

	p := NewNetworkPool("10.0.0.0", 256)

	ip, ok = p.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)

	ip, ok = p.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.4")
	c.Check(ok, Equals, true)
}

func (s *NetworkPoolSuite) TestAcquireAll(c *C) {
	p := NewNetworkPool("10.0.0.0", 256)

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}

func (s *NetworkPoolSuite) TestJson(c *C) {
	var i, j IP
	var ok bool

	p := NewNetworkPool("10.0.0.0", 1)

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
