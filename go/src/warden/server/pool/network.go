package pool

import (
	"bytes"
	"container/list"
	"net"
	"sync"
)

type Network struct {
	sync.Mutex

	// Use this /30 network as offset for the network pool
	StartAddress string

	// Pool this many /30 networks
	Size int

	// Actual pool
	pool *list.List
}

func IPToUint32(i net.IP) uint32 {
	i = i.To4()
	if i == nil {
		panic("Expected IPv4")
	}

	var u uint32

	u |= uint32(i[0]) << 24
	u |= uint32(i[1]) << 16
	u |= uint32(i[2]) << 8
	u |= uint32(i[3]) << 0

	return u
}

func Uint32ToIP(u uint32) net.IP {
	var a, b, c, d byte

	a = byte((u >> 24) & 0xff)
	b = byte((u >> 16) & 0xff)
	c = byte((u >> 8) & 0xff)
	d = byte((u >> 0) & 0xff)

	return net.IPv4(a, b, c, d)
}

func (n *Network) init() {
	if n.pool == nil {
		n.pool = list.New()

		ip := net.ParseIP(n.StartAddress)
		if ip == nil {
			panic("Invalid start address")
		}

		// Mask IP
		ip = ip.Mask(net.IPv4Mask(255, 255, 255, 252))

		// Convert to unsigned integer
		u := IPToUint32(ip)

		for i := 0; i < n.Size; i++ {
			n.pool.PushBack(Uint32ToIP(u))

			// Next network
			u += 4
		}
	}
}

func (n *Network) Acquire() *net.IP {
	n.Lock()
	defer n.Unlock()

	n.init()

	e := n.pool.Front()
	if e == nil {
		return nil
	}

	ip := n.pool.Remove(e).(net.IP)

	return &ip
}

func (n *Network) Release(ip net.IP) {
	n.Lock()
	defer n.Unlock()

	n.init()

	n.pool.PushBack(ip)
}

func (n *Network) Remove(ip net.IP) bool {
	n.Lock()
	defer n.Unlock()

	n.init()

	for e := n.pool.Front(); e != nil; e = e.Next() {
		ip_ := e.Value.(net.IP)
		if bytes.Equal(ip, ip_) {
			n.pool.Remove(e)
			return true
		}
	}

	return false
}
