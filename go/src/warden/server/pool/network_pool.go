package pool

import (
	"bytes"
	"encoding/json"
	"errors"
	"net"
)

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

type IP net.IP

func (x IP) String() string {
	return net.IP(x).String()
}

func (x IP) Add(i uint32) IP {
	y := IPToUint32(net.IP(x))
	y += i
	return IP(Uint32ToIP(y))
}

func (x IP) MarshalJSON() ([]byte, error) {
	return json.Marshal(x.String())
}

func (x *IP) UnmarshalJSON(data []byte) error {
	var s string

	if x == nil {
		return errors.New("pool.IP: UnmarshalJSON on nil pointer")
	}

	err := json.Unmarshal(data, &s)
	if err != nil {
		return err
	}

	y := net.ParseIP(s)
	if y == nil {
		return errors.New("pool.IP: Invalid IP")
	}

	*x = IP(y)

	return nil
}

func (x IP) Next() Poolable {
	return x.Add(4)
}

func (x IP) Equals(y Poolable) bool {
	z, ok := y.(IP)
	return ok && bytes.Equal(x, z)
}

type NetworkPool struct {
	*Pool
}

func NewNetworkPool(addr string, size int) *NetworkPool {
	var x IP

	err := json.Unmarshal([]byte(`"`+addr+`"`), &x)
	if err != nil {
		panic(err)
	}

	p := &NetworkPool{}
	p.Pool = NewPool(x, size)
	return p
}

func (p *NetworkPool) Acquire() (x IP, ok bool) {
	y, ok := p.Pool.Acquire()
	if ok {
		x = y.(IP)
	}

	return
}

func (p *NetworkPool) Release(x IP) {
	p.Pool.Release(x)
}

func (p *NetworkPool) Remove(x IP) bool {
	return p.Pool.Remove(x)
}
