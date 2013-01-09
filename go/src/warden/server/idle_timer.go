package server

import (
	"sync"
	"time"
)

type IdleTimer struct {
	sync.RWMutex

	C chan bool
	m chan int
	D chan time.Duration
}

func NewIdleTimer(d time.Duration) *IdleTimer {
	x := &IdleTimer{
		C: make(chan bool),
		m: make(chan int),
		D: make(chan time.Duration),
	}

	go x.loop()

	x.D <- d

	return x
}

func (x *IdleTimer) loop() {
	var C chan bool
	var m chan int = x.m
	var d time.Duration
	var i, y int

	for ok := true; ok; {
		var z <-chan time.Time

		if y == 0 && d > 0 {
			z = time.After(d)
		}

		select {
		case d = <-x.D: // New timeout
		case i, ok = <-m: // Ref/UnRef
			y += i
			C = nil

		case <-z: // Timeout
			C = x.C

		case C <- true:
			ok = false
		}
	}

	x.Stop()

	close(x.C)
}

func (x *IdleTimer) drain() {
	x.RLock()
	m := x.m
	x.RUnlock()

	// Drain modifier channel to unblock senders
	if m != nil {
		go func() {
			for _ = range m {
			}
		}()
	}
}

func (x *IdleTimer) Stop() {
	x.drain()

	// There can not be pending senders after the write lock has been acquired
	x.Lock()
	defer x.Unlock()

	if x.m != nil {
		close(x.m)
		x.m = nil
	}
}

func (x *IdleTimer) mark(i int) bool {
	x.RLock()
	defer x.RUnlock()

	if x.m != nil {
		x.m <- i
		return true
	}

	return false
}

func (x *IdleTimer) Ref() bool {
	return x.mark(1)
}

func (x *IdleTimer) Unref() bool {
	return x.mark(-1)
}
