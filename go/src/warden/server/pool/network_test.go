package pool

import (
	. "launchpad.net/gocheck"
	"net"
)

type NetworkSuite struct{}

var _ = Suite(&NetworkSuite{})

func (s *NetworkSuite) TestAcquire(c *C) {
	var ip net.IP
	var ok bool

	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.4")
	c.Check(ok, Equals, true)
}

func (s *NetworkSuite) TestAcquireAll(c *C) {
	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	for i := 0; i < 256; i++ {
		_, ok := n.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := n.Acquire()
	c.Check(ok, Equals, false)
}

func (s *NetworkSuite) TestRelease(c *C) {
	var ip net.IP
	var ok bool

	n := &Network{StartAddress: "10.0.0.0", Size: 1}

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)

	_, ok = n.Acquire()
	c.Check(ok, Equals, false)

	n.Release(ip)

	ip, ok = n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)
}

func (s *NetworkSuite) TestRemove(c *C) {
	n := &Network{StartAddress: "10.0.0.0", Size: 2}

	n.Remove(net.ParseIP("10.0.0.0"))

	ip, ok := n.Acquire()
	c.Check(ip.String(), Equals, "10.0.0.4")
	c.Check(ok, Equals, true)
}
