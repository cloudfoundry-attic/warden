package server

import (
	"fmt"
	"log"
	"os/exec"
	"path"
	"time"
	"warden/protocol"
	"warden/server/config"
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
	r chan *Request
	s *Server

	State  State
	Id     string
	Handle string
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
	c.r = make(chan *Request)
	c.s = s

	c.State = StateBorn
	c.Id = NextId()
	c.Handle = c.Id

	return c
}

func (c *LinuxContainer) Execute(r *Request) {
	c.r <- r
}

func (c *LinuxContainer) ContainerPath() string {
	return path.Join(c.c.Server.ContainerDepotPath, c.Handle)
}

func (c *LinuxContainer) Run() {
	for r := range c.r {
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
}

func (c *LinuxContainer) runBorn(r *Request) {
	switch req := r.r.(type) {
	case *protocol.CreateRequest:
		c.DoCreate(r, req)
		close(r.done)

	default:
		r.WriteInvalidState(string(c.State))
		close(r.done)
	}
}

func (c *LinuxContainer) runActive(r *Request) {
	switch req := r.r.(type) {
	case *protocol.StopRequest:
		c.DoStop(r, req)
		close(r.done)

	case *protocol.DestroyRequest:
		c.DoDestroy(r, req)
		close(r.done)

	default:
		r.WriteInvalidState(string(c.State))
		close(r.done)
	}
}

func (c *LinuxContainer) runStopped(r *Request) {
	switch req := r.r.(type) {
	case *protocol.DestroyRequest:
		c.DoDestroy(r, req)
		close(r.done)

	default:
		r.WriteInvalidState(string(c.State))
		close(r.done)
	}
}

func (c *LinuxContainer) runDestroyed(r *Request) {
	switch r.r.(type) {
	default:
		r.WriteInvalidState(string(c.State))
		close(r.done)
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

	// Override handle if specified
	if h := req.GetHandle(); h != "" {
		c.Handle = h
	}

	res := &protocol.CreateResponse{}
	res.Handle = &c.Handle

	// Create
	cmd = exec.Command(path.Join(c.c.Server.ContainerScriptPath, "create.sh"), c.ContainerPath())
	cmd.Env = append(cmd.Env, fmt.Sprintf("id=%s", c.Id))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_host_ip=%s", "10.0.0.1"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("network_container_ip=%s", "10.0.0.2"))
	cmd.Env = append(cmd.Env, fmt.Sprintf("user_uid=%d", 10000))
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

func (c *LinuxContainer) DoStop(x *Request, req *protocol.StopRequest) {
	var cmd *exec.Cmd

	done := make(chan error, 1)

	cmd = exec.Command(path.Join(c.ContainerPath(), "stop.sh"))

	// Don't wait for graceful stop if kill=true
	if req.GetKill() {
		cmd.Args = append(cmd.Args, "-w", "0")
	}

	// Run command in background
	go func() {
		done <- runCommand(cmd)
	}()

	// Wait for completion if background=false
	if !req.GetBackground() {
		<-done
	}

	c.State = StateStopped

	res := &protocol.StopResponse{}
	x.WriteResponse(res)
}

func (c *LinuxContainer) DoDestroy(x *Request, req *protocol.DestroyRequest) {
	var cmd *exec.Cmd
	var err error

	cmd = exec.Command(path.Join(c.ContainerPath(), "destroy.sh"))

	err = runCommand(cmd)
	if err != nil {
		x.WriteErrorResponse("error")
		return
	}

	c.State = StateDestroyed
	c.s.R.Unregister(c)

	res := &protocol.DestroyResponse{}
	x.WriteResponse(res)
}
