package test

import (
	"code.google.com/p/goprotobuf/proto"
	. "launchpad.net/gocheck"
	"warden/protocol"
)

type LifecycleSuite struct {
	s *server
	c *client
}

var _ = Suite(&LifecycleSuite{})

func (s *LifecycleSuite) SetUpSuite(c *C) {
	s.s = &server{}
	s.s.Initialize()
	s.s.Start()
}

func (s *LifecycleSuite) TearDownSuite(c *C) {
	s.s.Stop()
}

func (s *LifecycleSuite) SetUpTest(c *C) {
	var err error

	s.c, err = NewClient(s.s.UnixDomainPath)
	if err != nil {
		panic(err)
	}
}

func (s *LifecycleSuite) TestCreate(c *C) {
	var err error

	p := &protocol.CreateRequest{}
	q, err := s.c.Create(p)
	c.Check(err, IsNil)
	c.Check(q.GetHandle(), Not(Equals), "")
}

func (s *LifecycleSuite) TestCreateWithHandle(c *C) {
	var err error
	var q *protocol.CreateResponse

	h := "test_handle"

	p := &protocol.CreateRequest{}
	p.Handle = &h

	q, err = s.c.Create(p)
	c.Check(err, IsNil)
	c.Check(q.GetHandle(), Equals, h)

	// It shouldn't be possible to create a container with the same handle
	q, err = s.c.Create(p)
	c.Check(err, Not(IsNil))
	c.Check(err.Error(), Matches, ".*already exists.*")
}

func (s *LifecycleSuite) TestDestroy(c *C) {
	var err error
	var u *protocol.CreateRequest
	var v *protocol.CreateResponse
	var w *protocol.DestroyRequest

	// Destroying an unknown container handle should fail
	w = &protocol.DestroyRequest{Handle: proto.String("some_handle")}
	_, err = s.c.Destroy(w)
	c.Check(err.Error(), Matches, ".*unknown.*")

	// Create container
	u = &protocol.CreateRequest{}
	v, err = s.c.Create(u)
	c.Check(err, IsNil)

	// Destroy container
	w = &protocol.DestroyRequest{Handle: proto.String(v.GetHandle())}
	_, err = s.c.Destroy(w)
	c.Check(err, IsNil)

	// Destroying a container twice should fail
	w = &protocol.DestroyRequest{Handle: proto.String(v.GetHandle())}
	_, err = s.c.Destroy(w)
	c.Check(err.Error(), Matches, ".*unknown.*")
}
