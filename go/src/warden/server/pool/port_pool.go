package pool

import (
	"encoding/json"
	"errors"
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

type Port uint16

func (x Port) MarshalJSON() ([]byte, error) {
	return json.Marshal(uint16(x))
}

func (x *Port) UnmarshalJSON(data []byte) error {
	var y uint16

	if x == nil {
		return errors.New("pool.Port: UnmarshalJSON on nil pointer")
	}

	err := json.Unmarshal(data, &y)
	if err != nil {
		return err
	}

	*x = Port(y)

	return nil
}

func (x Port) Next() Poolable {
	return Port(x + 1)
}

func (x Port) Equals(y Poolable) bool {
	z, ok := y.(Port)
	return ok && x == z
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
	p.Pool = NewPool(Port(uint16(start)), size)

	return p
}

func (p *PortPool) Acquire() (x Port, ok bool) {
	y, ok := p.Pool.Acquire()
	if ok {
		x = y.(Port)
	}

	return
}

func (p *PortPool) Release(x Port) {
	p.Pool.Release(x)
}

func (p *PortPool) Remove(x Port) bool {
	return p.Pool.Remove(x)
}
