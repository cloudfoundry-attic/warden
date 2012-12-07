package pool

import (
	. "launchpad.net/gocheck"
	"net"
)

type NetworkSuite struct{}

var _ = Suite(&NetworkSuite{})

func (s *NetworkSuite) TestAcquire(c *C) {
	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	c.Check(n.Acquire().String(), Equals, "10.0.0.0")
	c.Check(n.Acquire().String(), Equals, "10.0.0.4")
}

func (s *NetworkSuite) TestAcquireAll(c *C) {
	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	for i := 0; i < 256; i++ {
		c.Check(n.Acquire(), Not(IsNil))
	}

	c.Check(n.Acquire(), IsNil)
}

func (s *NetworkSuite) TestRelease(c *C) {
	var ip1, ip2 *net.IP

	n := &Network{StartAddress: "10.0.0.0", Size: 1}

	ip1 = n.Acquire()
	c.Check(ip1, Not(IsNil))

	ip2 = n.Acquire()
	c.Check(ip2, IsNil)

	n.Release(*ip1)

	ip2 = n.Acquire()
	c.Check(ip2, Not(IsNil))
}

func (s *NetworkSuite) TestRemove(c *C) {
	n := &Network{StartAddress: "10.0.0.0", Size: 2}

	n.Remove(net.ParseIP("10.0.0.0"))

	c.Check(n.Acquire().String(), Equals, "10.0.0.4")
}
