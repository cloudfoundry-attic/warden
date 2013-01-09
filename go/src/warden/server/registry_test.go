package server

import (
	. "launchpad.net/gocheck"
	"sort"
)

type FakeContainer string

func (x FakeContainer) GetHandle() string {
	return string(x)
}

func (x FakeContainer) Run() {
	panic("run")
}

func (x FakeContainer) Execute(r *Request) {
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

func (s *RegistrySuite) TestHandles(c *C) {
	var err error

	err = s.Register(FakeContainer("a"))
	c.Check(err, IsNil)

	err = s.Register(FakeContainer("b"))
	c.Check(err, IsNil)

	h := s.Handles()
	sort.Strings(h)
	c.Check(h, DeepEquals, []string{"a", "b"})
}
