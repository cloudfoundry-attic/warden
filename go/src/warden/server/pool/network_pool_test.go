package pool

import (
	"encoding/json"
	. "launchpad.net/gocheck"
)

type NetworkSuite struct{}

var _ = Suite(&NetworkSuite{})

func (s *NetworkSuite) TestAcquire(c *C) {
	var ip IP
	var ok bool

	n := NewNetworkPool("10.0.0.0", 256)

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.4")
	c.Check(ok, Equals, true)
}

func (s *NetworkSuite) TestAcquireAll(c *C) {
	n := NewNetworkPool("10.0.0.0", 256)

	for i := 0; i < 256; i++ {
		_, ok := n.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := n.Acquire()
	c.Check(ok, Equals, false)
}

func (s *NetworkSuite) TestJson(c *C) {
	var i, j IP
	var ok bool

	n := NewNetworkPool("10.0.0.0", 1)

	i, ok = n.Acquire()
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
