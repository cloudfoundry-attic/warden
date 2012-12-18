package server

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"os/exec"
	"path"
	"time"
	"warden/protocol"
	"warden/server/config"
	"warden/server/pool"
)

type Container interface {
	GetHandle() string
	Run()
	Execute(*Request)
}

type State string

const (
	StateBorn      = State("born")
	StateActive    = State("active")
	StateStopped   = State("stopped")
	StateDestroyed = State("destroyed")
)

type Job struct {
}

type LinuxContainer struct {
	c *config.Config
	r chan chan *Request
	s *Server

	State  State
	Id     string
	Handle string

	Network *pool.IP
	Ports   []*pool.Port
	UserId  *pool.UserId

	IdleTimeout time.Duration
}

func (c *LinuxContainer) GetState() State {
	return c.State
}

func (c *LinuxContainer) GetId() string {
	return c.Id
}

func (c *LinuxContainer) GetHandle() string {
	return c.Handle
}

func NewContainer(s *Server, cfg *config.Config) *LinuxContainer {
	c := &LinuxContainer{}

	c.c = cfg
	c.r = make(chan chan *Request)
	c.s = s

	c.State = StateBorn
	c.Id = NextId()
	c.Handle = c.Id

	// Initialize port slice
	c.Ports = make([]*pool.Port, 0)

	// Initialize idle timeout
	c.IdleTimeout = time.Duration(c.c.Server.ContainerGraceTime) * time.Second

	return c
}

// Acquires pooled resources.
// If a resource is already bound to the container, remove it from its pool.
// This behavior is required for resuming from a snapshot.
func (c *LinuxContainer) Acquire() error {
	if c.Network != nil {
		c.c.NetworkPool.Remove(*c.Network)
	} else {
		p, ok := c.c.NetworkPool.Acquire()
		if !ok {
			return errors.New("LinuxContainer: Cannot acquire network")
		}

		c.Network = &p
	}

	if c.Ports != nil {
		for _, p := range c.Ports {
			c.c.PortPool.Remove(*p)
		}
	}

	if c.UserId != nil {
		c.c.UserPool.Remove(*c.UserId)
	} else {
		p, ok := c.c.UserPool.Acquire()
		if !ok {
			return errors.New("LinuxContainer: Cannot acquire user ID")
		}

		c.UserId = &p
	}

	return nil
}

// Releases pooled resources.
func (c *LinuxContainer) Release() error {
	if c.Network != nil {
		c.c.NetworkPool.Release(*c.Network)
		c.Network = nil
	}

	if len(c.Ports) > 0 {
		for _, p := range c.Ports {
			c.c.PortPool.Release(*p)
		}

		c.Ports = make([]*pool.Port, 0)
	}

	if c.UserId != nil {
		c.c.UserPool.Release(*c.UserId)
		c.UserId = nil
	}

	return nil
}

func (c *LinuxContainer) snapshotPath() string {
	return path.Join(c.ContainerPath(), "etc", "snapshot.json")
}

// markDirty removes the snapshot file, preventing restore on restart.
func (c *LinuxContainer) markDirty() error {
	err := os.Remove(c.snapshotPath())
	if err != nil {
		return err
	}

	return nil
}

// markClean writes a snapshot, allowing restore on restart.
func (c *LinuxContainer) markClean() error {
	var err error

	x := path.Join(c.ContainerPath(), "tmp")
	y, err := ioutil.TempFile(x, "snapshot")
	if err != nil {
		return err
	}

	z := bufio.NewWriter(y)

	e := json.NewEncoder(z)
	err = e.Encode(c)
	if err != nil {
		return err
	}

	err = z.Flush()
	if err != nil {
		return err
	}

	y.Close()

	// Move the snapshot to its destination.
	// It is not written in place because that cannot be done atomically.
	err = os.Rename(y.Name(), c.snapshotPath())
	if err != nil {
		return err
	}

	return nil
}

func (c *LinuxContainer) Execute(r *Request) {
	x := <-c.r
	if x != nil {
		x <- r
	} else {
		r.WriteErrorResponse("Container doesn't accept new requests")
	}
}

func (c *LinuxContainer) ContainerPath() string {
	return path.Join(c.c.Server.ContainerDepotPath, c.Handle)
}

func (c *LinuxContainer) Run() {
	var i *IdleTimer
	var d = c.IdleTimeout

	// Use ridiculous idle timeout when it is invalid
	if d <= 0 {
		d = 7 * 24 * time.Hour
	}

	i = NewIdleTimer(c.IdleTimeout)
	defer i.Stop()

	// Request channel
	x := make(chan *Request, 1)

	for stop := false; !stop; {
		select {
		case <-i.C:
			stop = true
		case c.r <- x:
			i.Ref()

			r := <-x
			go func() {
				<-r.done
				i.Unref()
			}()

			c.runRequest(r)
		}
	}

	close(c.r)

	err := c.doDestroy()
	if err != nil {
		// Warnf
		log.Printf("Error destroying container: %s\n", err)
	}
}

func (c *LinuxContainer) runRequest(r *Request) {
	t1 := time.Now()

	switch c.State {
	case StateBorn:
		c.runBorn(r)

	case StateActive:
		c.runActive(r)

	case StateStopped:
		c.runStopped(r)

	case StateDestroyed:
		c.runDestroyed(r)

	default:
		panic("Unknown state: " + c.State)
	}

	t2 := time.Now()

	log.Printf("took: %.6fs\n", t2.Sub(t1).Seconds())
}

func (c *LinuxContainer) writeInvalidState(r *Request) {
	r.WriteErrorResponse(fmt.Sprintf("Cannot execute request in state: %s", c.State))
}

func (c *LinuxContainer) runBorn(r *Request) {
	switch req := r.r.(type) {
	case *protocol.CreateRequest:
		c.markDirty()
		c.DoCreate(r, req)
		c.markClean()

	default:
		c.writeInvalidState(r)
	}
}

func (c *LinuxContainer) runActive(r *Request) {
	switch req := r.r.(type) {
	case *protocol.StopRequest:
		c.markDirty()
		c.DoStop(r, req)
		c.markClean()

	case *protocol.DestroyRequest:
		c.markDirty()
		c.DoDestroy(r, req)

	default:
		c.writeInvalidState(r)
	}
}

func (c *LinuxContainer) runStopped(r *Request) {
	switch req := r.r.(type) {
	case *protocol.DestroyRequest:
		c.markDirty()
		c.DoDestroy(r, req)

	default:
		c.writeInvalidState(r)
	}
}

func (c *LinuxContainer) runDestroyed(r *Request) {
	switch r.r.(type) {
	default:
		c.writeInvalidState(r)
	}
}

func runCommand(cmd *exec.Cmd) error {
	log.Printf("Run: %#v\n", cmd.Args)
	out, err := cmd.CombinedOutput()
	if err != nil {
		log.Printf("Error running %s: %s\n", cmd.Args[0], err)
		log.Printf("Output: %s\n", out)
	}

	return err
}

func (c *LinuxContainer) DoCreate(x *Request, req *protocol.CreateRequest) {
	var cmd *exec.Cmd
	var err error

	err = c.Acquire()
	if err != nil {
		x.WriteErrorResponse(err.Error())
		return
	}

	// Override handle if specified
	if h := req.GetHandle(); h != "" {
		c.Handle = h
	}

	// Override idle timeout if specified
	if y := req.GraceTime; y != nil {
		c.IdleTimeout = time.Duration(*y) * time.Second
	}

	res := &protocol.CreateResponse{}
	res.Handle = &c.Handle

	// Create
	cmd = exec.Command(path.Join(c.c.Server.ContainerScriptPath, "create.sh"), c.ContainerPath())
	cmd.Env = append(cmd.Env, fmt.Sprintf("id=%s", c.Id))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_host_ip=%s", c.Network.Add(1).String()))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_container_ip=%s", c.Network.Add(2).String()))
	cmd.Env = append(cmd.Env, fmt.Sprintf("user_uid=%d", int(*c.UserId)))
	cmd.Env = append(cmd.Env, fmt.Sprintf("rootfs_path=%s", c.c.Server.ContainerRootfsPath))

	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	// Start
	cmd = exec.Command(path.Join(c.ContainerPath(), "start.sh"))
	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	c.State = StateActive
	c.s.R.Register(c)

	x.WriteResponse(res)
}

func (c *LinuxContainer) doStop(kill bool, background bool) error {
	var x *exec.Cmd
	var err error

	x = exec.Command(path.Join(c.ContainerPath(), "stop.sh"))

	// Don't wait for graceful stop if kill=true
	if kill {
		x.Args = append(x.Args, "-w", "0")
	}

	errc := make(chan error, 1)
	go func() {
		errc <- runCommand(x)
	}()

	// Wait for completion if background=false
	if !background {
		err = <-errc
		if err != nil {
			return err
		}
	}

	c.State = StateStopped

	return nil
}

func (c *LinuxContainer) DoStop(x *Request, req *protocol.StopRequest) {
	var err error

	err = c.doStop(req.GetKill(), req.GetBackground())
	if err != nil {
		x.WriteErrorResponse(err.Error())
		return
	}

	res := &protocol.StopResponse{}
	x.WriteResponse(res)
}

func (c *LinuxContainer) doDestroy() error {
	var x *exec.Cmd
	var err error

	x = exec.Command(path.Join(c.ContainerPath(), "destroy.sh"))
	err = runCommand(x)
	if err != nil {
		return err
	}

	c.State = StateDestroyed
	c.s.R.Unregister(c)

	// Remove directory
	err = os.RemoveAll(c.ContainerPath())
	if err != nil {
		panic(err)
	}

	return nil
}

func (c *LinuxContainer) DoDestroy(x *Request, req *protocol.DestroyRequest) {
	var err error

	err = c.doDestroy()
	if err != nil {
		x.WriteErrorResponse(err.Error())
		return
	}

	res := &protocol.DestroyResponse{}
	x.WriteResponse(res)
}
