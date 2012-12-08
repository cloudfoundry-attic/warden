package pool

import (
	"fmt"
	"io/ioutil"
	"os"
)

func ipLocalPortRange() [2]uint16 {
	f, err := os.Open("/proc/sys/net/ipv4/ip_local_port_range")
	if err != nil {
		panic(err)
	}

	defer f.Close()

	b, err := ioutil.ReadAll(f)
	if err != nil {
		panic(err)
	}

	var x [2]uint16

	n, err := fmt.Sscan(string(b), &x[0], &x[1])
	if n != 2 {
		panic(err)
	}

	return x
}

type port struct {
	p uint16
}

func (x port) Next() Poolable {
	return port{x.p + 1}
}

func (x port) Equals(y Poolable) bool {
	z, ok := y.(port)
	return ok && x.p == z.p
}

type PortPool struct {
	*Pool
}

func NewPortPool(start int, size int) *PortPool {
	if start < 0 {
		x := ipLocalPortRange()
		start = int(x[1])
	}

	// Don't use ports >= 65000
	max := 65000

	if start < 1024 || start >= max {
		panic("invalid start port")
	}

	if size == 0 {
		size = max - start
	}

	if size == 0 || start+size > max {
		panic("invalid size")
	}

	p := &PortPool{}
	p.Pool = NewPool(port{uint16(start)}, size)

	return p
}

func (p *PortPool) Acquire() (x uint16, ok bool) {
	y, ok := p.Pool.Acquire()
	if ok {
		x = y.(port).p
	}

	return
}

func (p *PortPool) Release(x uint16) {
	p.Pool.Release(port{x})
}

func (p *PortPool) Remove(x uint16) bool {
	return p.Pool.Remove(port{x})
}
