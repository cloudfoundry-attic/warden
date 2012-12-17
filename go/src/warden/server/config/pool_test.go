package config

import (
	. "launchpad.net/gocheck"
	"launchpad.net/goyaml"
)

type PoolSuite struct {
	Config
}

var _ = Suite(&PoolSuite{})

func (s *PoolSuite) SetUpTest(c *C) {
	var b = []byte(`
network:
  pool_start_address: 10.0.0.0
  pool_size: 1
user:
  pool_start_uid: 37
  pool_size: 1
`)

	s.Config = DefaultConfig()

	goyaml.Unmarshal(b, &s.Config)

	s.Config.Process()
}

func (s *PoolSuite) TestNetworkPoolAcquire(c *C) {
	c.Assert(s.NetworkPool, Not(IsNil))

	x, ok := s.NetworkPool.Acquire()
	c.Check(x.String(), Equals, "10.0.0.0")
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestPortPoolAcquire(c *C) {
	c.Assert(s.PortPool, Not(IsNil))

	x, ok := s.PortPool.Acquire()
	c.Check(x >= 32768 && x < 65000, Equals, true)
	c.Check(ok, Equals, true)
}

func (s *PoolSuite) TestUserPoolAcquire(c *C) {
	c.Assert(s.UserPool, Not(IsNil))

	x, ok := s.UserPool.Acquire()
	c.Check(int(x), Equals, 37)
	c.Check(ok, Equals, true)
}
