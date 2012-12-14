package server

import (
	. "launchpad.net/gocheck"
	"warden/protocol"
)

type FakeContainer string

func (x FakeContainer) Handle() string {
	return string(x)
}

func (x FakeContainer) Run() {
	panic("run")
}

func (x FakeContainer) Execute(c *Conn, r protocol.Request) {
	panic("execute")
}

type RegistrySuite struct {
	*Registry
}

var _ = Suite(&RegistrySuite{})

func (s *RegistrySuite) SetUpTest(c *C) {
	s.Registry = NewRegistry()
}

func (s *RegistrySuite) TestRegister(c *C) {
	var err error

	a := FakeContainer("a")

	err = s.Register(a)
	c.Check(err, IsNil)
	c.Check(s.Find("a"), Not(IsNil))

	err = s.Register(a)
	c.Check(err, Equals, ErrAlreadyRegistered)
}

func (s *RegistrySuite) TestUnregister(c *C) {
	var err error

	a := FakeContainer("a")

	err = s.Unregister(a)
	c.Check(err, Equals, ErrNotRegistered)

	err = s.Register(a)
	c.Check(err, IsNil)
	c.Check(s.Find("a"), Not(IsNil))

	err = s.Unregister(a)
	c.Check(err, IsNil)
	c.Check(s.Find("a"), IsNil)
}
