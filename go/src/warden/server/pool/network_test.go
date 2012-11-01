package pool

import (
	"net"
	"testing"
)

func testIP(t *testing.T, ip net.IP, expected string) {
	actual := ip.String()

	if expected != actual {
		t.Errorf("Expected %s, was: %s\n", expected, actual)
	}
}

func TestNetworkAcquire(t *testing.T) {
	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	var ip *net.IP

	ip = n.Acquire()
	testIP(t, *ip, "10.0.0.0")

	ip = n.Acquire()
	testIP(t, *ip, "10.0.0.4")
}

func TestNetworkAcquireAll(t *testing.T) {
	n := &Network{StartAddress: "10.0.0.0", Size: 256}

	for i := 0; i < 256; i++ {
		ip := n.Acquire()
		if ip == nil {
			t.Errorf("Expected Acquire() not to return nil\n")
			return
		}
	}

	ip := n.Acquire()
	if ip != nil {
		t.Errorf("Expected Acquire() to return nil\n")
		return
	}
}

func TestNetworkRelease(t *testing.T) {
	n := &Network{StartAddress: "10.0.0.0", Size: 1}

	var ip1, ip2 *net.IP

	ip1 = n.Acquire()

	ip2 = n.Acquire()
	if ip2 != nil {
		t.Errorf("Expected Acquire() to return nil\n")
		return
	}

	n.Release(*ip1)

	ip2 = n.Acquire()
	if ip2 == nil {
		t.Errorf("Expected Acquire() not to return nil\n")
		return
	}
}

func TestNetworkRemove(t *testing.T) {
	n := &Network{StartAddress: "10.0.0.0", Size: 2}

	n.Remove(net.ParseIP("10.0.0.0"))

	var ip *net.IP

	ip = n.Acquire()
	testIP(t, *ip, "10.0.0.4")
}
