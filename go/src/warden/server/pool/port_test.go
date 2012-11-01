package pool

import (
	"testing"
)

func testPort(t *testing.T, actual uint, expected uint) {
	if expected != actual {
		t.Errorf("Expected %d, was: %d\n", expected, actual)
	}
}

func TestPortAcquire(t *testing.T) {
	p := &Port{StartPort: 61000, Size: 256}

	var i *uint

	i = p.Acquire()
	testPort(t, *i, 61000)

	i = p.Acquire()
	testPort(t, *i, 61001)
}

func TestPortAcquireAll(t *testing.T) {
	p := &Port{StartPort: 61000, Size: 256}

	for i := 0; i < 256; i++ {
		i_ := p.Acquire()
		if i_ == nil {
			t.Errorf("Expected Acquire() not to return nil\n")
			return
		}
	}

	i_ := p.Acquire()
	if i_ != nil {
		t.Errorf("Expected Acquire() to return nil\n")
		return
	}
}

func TestPortRelease(t *testing.T) {
	p := &Port{StartPort: 61000, Size: 1}

	var i1, i2 *uint

	i1 = p.Acquire()

	i2 = p.Acquire()
	if i2 != nil {
		t.Errorf("Expected Acquire() to return nil\n")
		return
	}

	p.Release(*i1)

	i2 = p.Acquire()
	if i2 == nil {
		t.Errorf("Expected Acquire() not to return nil\n")
		return
	}
}

func TestPortRemove(t *testing.T) {
	p := &Port{StartPort: 61000, Size: 2}

	p.Remove(61000)

	var i *uint

	i = p.Acquire()
	testPort(t, *i, 61001)
}

func TestPortInit(t *testing.T) {
	p := &Port{}

	// Acquire to trigger init
	_ = p.Acquire()

	if p.StartPort == 0 {
		t.Error("Expected StartPort to not be 0")
	}

	if p.Size == 0 {
		t.Error("Expected Size to not be 0")
	}
}
