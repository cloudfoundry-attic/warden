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
}

func (s *IdleTimerSuite) TearDownTest(c *C) {
	s.IdleTimer.Stop()
}

func (s *IdleTimerSuite) TestFire(c *C) {
	var ok = false

	// Wait until the idle timer should be ready to fire
	time.Sleep(10 * time.Millisecond)

	select {
	case _, ok = <-s.C:
	default:
	}

	c.Check(ok, Equals, true)
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

	// Wait until the idle timer should be ready to fire
	time.Sleep(10 * time.Millisecond)

	select {
	case _, ok = <-s.C:
	default:
	}

	c.Check(ok, Equals, true)
}
