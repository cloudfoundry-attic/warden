package server

import (
	. "launchpad.net/gocheck"
	"time"
)

type IdleTimerSuite struct {
	*IdleTimer
}

var _ = Suite(&IdleTimerSuite{})

func (s *IdleTimerSuite) SetUpTest(c *C) {
	s.IdleTimer = NewIdleTimer(5 * time.Millisecond)
	s.IdleTimer.Start()
}

func (s *IdleTimerSuite) TearDownTest(c *C) {
	s.IdleTimer.Stop()
}

func (s *IdleTimerSuite) TestFire(c *C) {
	var a, b time.Time

	a = time.Now()
	<-s.C
	b = time.Now()

	// Check that it took at least 5ms for the timer to fire
	c.Check(b.Sub(a) > 5*time.Millisecond, Equals, true)
}

func (s *IdleTimerSuite) TestFireWithNewTimeout(c *C) {
	var a, b time.Time

	s.D <- 10 * time.Millisecond

	a = time.Now()
	<-s.C
	b = time.Now()

	// Check that it took at least 10ms for the timer to fire
	c.Check(b.Sub(a) > 10*time.Millisecond, Equals, true)
}

func (s *IdleTimerSuite) TestNoFire(c *C) {
	var ok = false

	// Wait until the idle timer should be ready to fire
	time.Sleep(10 * time.Millisecond)

	// Ref/unref to cancel fire, as it was not yet consumed
	s.Ref()
	s.Unref()

	select {
	case _, ok = <-s.C:
	default:
	}

	c.Check(ok, Equals, false)
}

func (s *IdleTimerSuite) TestRefUnref(c *C) {
	var ok bool

	s.Ref()

	// Wait until the idle timer should have been ready to fire
	time.Sleep(10 * time.Millisecond)

	select {
	case _, ok = <-s.C:
	default:
	}

	c.Check(ok, Equals, false)

	s.Unref()

	var a, b time.Time

	a = time.Now()
	<-s.C
	b = time.Now()

	// Check that it took at least 5ms for the timer to fire
	c.Check(b.Sub(a) > 5*time.Millisecond, Equals, true)
}
