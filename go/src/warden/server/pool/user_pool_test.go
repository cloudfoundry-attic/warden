package pool

import (
	"encoding/json"
	. "launchpad.net/gocheck"
)

type UserPoolSuite struct{}

var _ = Suite(&UserPoolSuite{})

func (s *UserPoolSuite) TestAcquire(c *C) {
	var x UserId
	var ok bool

	p := NewUserPool(10000, 256)

	x, ok = p.Acquire()
	c.Check(x, Equals, UserId(10000))
	c.Check(ok, Equals, true)

	x, ok = p.Acquire()
	c.Check(x, Equals, UserId(10001))
	c.Check(ok, Equals, true)
}

func (s *UserPoolSuite) TestAcquireAll(c *C) {
	p := NewUserPool(10000, 256)

	for i := 0; i < 256; i++ {
		_, ok := p.Acquire()
		c.Check(ok, Equals, true)
	}

	_, ok := p.Acquire()
	c.Check(ok, Equals, false)
}

func (s *UserPoolSuite) TestJson(c *C) {
	var i, j UserId
	var ok bool

	p := NewUserPool(10000, 1)

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
