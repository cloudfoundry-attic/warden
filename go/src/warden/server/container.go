package server

import (
	"encoding/json"
	"errors"
	"fmt"
	steno "github.com/cloudfoundry/gosteno"
	"io"
	"io/ioutil"
	"os"
	"os/exec"
	"path"
	"strconv"
	"strings"
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

type LinuxContainer struct {
	c *config.Config
	r chan chan *Request
	s *Server
	l steno.Logger

	State  State
	Id     string
	Handle string

	Network *pool.IP
	Ports   []*pool.Port
	UserId  *pool.UserId

	IdleTimeout time.Duration

	// The map needs to use a string key because that cleanly serializes to JSON
	JobId int
	Jobs  map[string]*Job
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

	// Setup container-specific logger
	l := steno.NewLogger("container")
	c.l = steno.NewTaggedLogger(l, map[string]string{"id": c.Id})

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
		c.l.Warnf("Unable to remove snapshot: %s", err)
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
		c.l.Warnf("Unable to create snapshot file: %s", err)
		return err
	}

	// The tempfile must be closed whatever happens
	defer y.Close()

	b, err := json.Marshal(c)
	if err != nil {
		c.l.Warnf("Unable to encode snapshot: %s", err)
		return err
	}

	c.l.Debugf("Snapshot: %s", string(b))

	_, err = y.Write(b)
	if err != nil {
		return err
	}

	y.Close()

	// Move the snapshot to its destination.
	// It is not written in place because that cannot be done atomically.
	err = os.Rename(y.Name(), c.snapshotPath())
	if err != nil {
		c.l.Warnf("Unable to rename snapshot in place: %s", err)
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
	i := NewIdleTimer(0)
	i.Start()
	i.D <- c.IdleTimeout
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

			// Overwrite idle timeout
			i.D <- c.IdleTimeout
		}
	}

	close(c.r)

	err := c.doDestroy()
	if err != nil {
		c.l.Warnf("Error destroying container: %s", err)
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

	c.l.Debugf("took: %.6fs", t2.Sub(t1).Seconds())
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

	case *protocol.SpawnRequest:
		c.markDirty()
		c.DoSpawn(r, req)
		c.markClean()

	case *protocol.LinkRequest:
		c.DoLink(r, req)

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

	// Add handle to logger
	c.l = steno.NewTaggedLogger(c.l, map[string]string{"handle": c.Handle})

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

func (c *LinuxContainer) spawn(a []string, e []string, r io.Reader) (int, error) {
	c.JobId++
	i := c.JobId

	w := path.Join(c.ContainerPath(), "jobs", fmt.Sprintf("%d", i))
	err := os.MkdirAll(w, 0700)
	if err != nil {
		c.l.Warnf("os.MkdirAll: %s", err)
		return -1, err
	}

	j := &Job{
		SpawnerBin: path.Join(c.ContainerPath(), "bin", "iomux-spawn"),
		LinkerBin:  path.Join(c.ContainerPath(), "bin", "iomux-link"),
		WorkDir:    w,

		Args:  a,
		Env:   e,
		Stdin: r,
	}

	c.l.Debugf("Spawn: %#v", *j)

	j.Spawn()

	if c.Jobs == nil {
		c.Jobs = make(map[string]*Job)
	}

	c.Jobs[strconv.Itoa(i)] = j

	return i, nil
}

type jobCreatingRequest interface {
	resourceLimitingRequest
	GetPrivileged() bool
	GetScript() string
}

func (c *LinuxContainer) createJob(x jobCreatingRequest) (int, error) {
	var a []string
	var e []string
	var r io.Reader

	a = append(a, path.Join(c.ContainerPath(), "bin", "wsh"))

	a = append(a, "--socket", path.Join(c.ContainerPath(), "run", "wshd.sock"))

	user := "vcap"
	if x.GetPrivileged() {
		user = "root"
	}

	a = append(a, "--user", user)

	a = append(a, "/bin/bash")

	e = formatResourceLimits(*c.c, x)

	r = strings.NewReader(x.GetScript())

	return c.spawn(a, e, r)
}

func (c *LinuxContainer) DoSpawn(x *Request, req *protocol.SpawnRequest) {
	i, err := c.createJob(req)
	if err != nil {
		y := &protocol.ErrorResponse{}
		y.Message = new(string)
		*y.Message = err.Error()
		x.WriteResponse(y)
	} else {
		y := &protocol.SpawnResponse{}
		y.JobId = new(uint32)
		*y.JobId = uint32(i)
		x.WriteResponse(y)
	}
}

func (c *LinuxContainer) doLink(x *Request, j *Job) {
	cstdout := make(chan []byte)
	cstderr := make(chan []byte)
	cstatus := make(chan int)

	rout, wout := io.Pipe()
	rerr, werr := io.Pipe()

	// Stdout
	go func() {
		b, err := ioutil.ReadAll(rout)
		if err != nil {
			panic(err)
		}

		cstdout <- b
	}()

	// Stderr
	go func() {
		b, err := ioutil.ReadAll(rerr)
		if err != nil {
			panic(err)
		}

		cstderr <- b
	}()

	// Exit status
	go func() {
		cstatus <- j.Link()
	}()

	j.Stdout.Add(wout)
	j.Stderr.Add(werr)

	stdout := string(<-cstdout)
	stderr := string(<-cstderr)
	status := uint32(<-cstatus)

	y := &protocol.LinkResponse{}
	y.ExitStatus = &status
	y.Stdout = &stdout
	y.Stderr = &stderr
	x.WriteResponse(y)

	x.Done()
}

func (c *LinuxContainer) DoLink(x *Request, req *protocol.LinkRequest) {
	i := int(req.GetJobId())
	j, ok := c.Jobs[strconv.Itoa(i)]
	if !ok {
		y := &protocol.ErrorResponse{}
		y.Message = new(string)
		*y.Message = "No such job"
		x.WriteResponse(y)
		return
	}

	x.Hijack()

	go c.doLink(x, j)
}

type resourceLimitingRequest interface {
	GetRlimits() *protocol.ResourceLimits
}

type resourceLimits struct {
	As         *int64
	Core       *int64
	Cpu        *int64
	Data       *int64
	Fsize      *int64
	Locks      *int64
	Memlock    *int64
	Msgqueue   *int64
	Nice       *int64
	Nofile     *int64
	Nproc      *int64
	Rss        *int64
	Rtprio     *int64
	Sigpending *int64
	Stack      *int64
}

func formatResourceLimits(c config.Config, r resourceLimitingRequest) []string {
	z := resourceLimits{}

	// Initialize defaults
	x := c.Server.ContainerRlimits
	if x.As != 0 {
		z.As = new(int64)
		*z.As = x.As
	}
	if x.Core != 0 {
		z.Core = new(int64)
		*z.Core = x.Core
	}
	if x.Cpu != 0 {
		z.Cpu = new(int64)
		*z.Cpu = x.Cpu
	}
	if x.Data != 0 {
		z.Data = new(int64)
		*z.Data = x.Data
	}
	if x.Fsize != 0 {
		z.Fsize = new(int64)
		*z.Fsize = x.Fsize
	}
	if x.Locks != 0 {
		z.Locks = new(int64)
		*z.Locks = x.Locks
	}
	if x.Memlock != 0 {
		z.Memlock = new(int64)
		*z.Memlock = x.Memlock
	}
	if x.Msgqueue != 0 {
		z.Msgqueue = new(int64)
		*z.Msgqueue = x.Msgqueue
	}
	if x.Nice != 0 {
		z.Nice = new(int64)
		*z.Nice = x.Nice
	}
	if x.Nofile != 0 {
		z.Nofile = new(int64)
		*z.Nofile = x.Nofile
	}
	if x.Nproc != 0 {
		z.Nproc = new(int64)
		*z.Nproc = x.Nproc
	}
	if x.Rss != 0 {
		z.Rss = new(int64)
		*z.Rss = x.Rss
	}
	if x.Rtprio != 0 {
		z.Rtprio = new(int64)
		*z.Rtprio = x.Rtprio
	}
	if x.Sigpending != 0 {
		z.Sigpending = new(int64)
		*z.Sigpending = x.Sigpending
	}
	if x.Stack != 0 {
		z.Stack = new(int64)
		*z.Stack = x.Stack
	}

	// Override from request
	y := r.GetRlimits()
	if y != nil {
		if y.As != nil {
			z.As = new(int64)
			*z.As = int64(*y.As)
		}
		if y.Core != nil {
			z.Core = new(int64)
			*z.Core = int64(*y.Core)
		}
		if y.Cpu != nil {
			z.Cpu = new(int64)
			*z.Cpu = int64(*y.Cpu)
		}
		if y.Data != nil {
			z.Data = new(int64)
			*z.Data = int64(*y.Data)
		}
		if y.Fsize != nil {
			z.Fsize = new(int64)
			*z.Fsize = int64(*y.Fsize)
		}
		if y.Locks != nil {
			z.Locks = new(int64)
			*z.Locks = int64(*y.Locks)
		}
		if y.Memlock != nil {
			z.Memlock = new(int64)
			*z.Memlock = int64(*y.Memlock)
		}
		if y.Msgqueue != nil {
			z.Msgqueue = new(int64)
			*z.Msgqueue = int64(*y.Msgqueue)
		}
		if y.Nice != nil {
			z.Nice = new(int64)
			*z.Nice = int64(*y.Nice)
		}
		if y.Nofile != nil {
			z.Nofile = new(int64)
			*z.Nofile = int64(*y.Nofile)
		}
		if y.Nproc != nil {
			z.Nproc = new(int64)
			*z.Nproc = int64(*y.Nproc)
		}
		if y.Rss != nil {
			z.Rss = new(int64)
			*z.Rss = int64(*y.Rss)
		}
		if y.Rtprio != nil {
			z.Rtprio = new(int64)
			*z.Rtprio = int64(*y.Rtprio)
		}
		if y.Sigpending != nil {
			z.Sigpending = new(int64)
			*z.Sigpending = int64(*y.Sigpending)
		}
		if y.Stack != nil {
			z.Stack = new(int64)
			*z.Stack = int64(*y.Stack)
		}
	}

	// Build list of environment variables
	a := make([]string, 0)
	if z.As != nil {
		a = append(a, fmt.Sprintf("RLIMIT_AS=%d", *z.As))
	}
	if z.Core != nil {
		a = append(a, fmt.Sprintf("RLIMIT_CORE=%d", *z.Core))
	}
	if z.Cpu != nil {
		a = append(a, fmt.Sprintf("RLIMIT_CPU=%d", *z.Cpu))
	}
	if z.Data != nil {
		a = append(a, fmt.Sprintf("RLIMIT_DATA=%d", *z.Data))
	}
	if z.Fsize != nil {
		a = append(a, fmt.Sprintf("RLIMIT_FSIZE=%d", *z.Fsize))
	}
	if z.Locks != nil {
		a = append(a, fmt.Sprintf("RLIMIT_LOCKS=%d", *z.Locks))
	}
	if z.Memlock != nil {
		a = append(a, fmt.Sprintf("RLIMIT_MEMLOCK=%d", *z.Memlock))
	}
	if z.Msgqueue != nil {
		a = append(a, fmt.Sprintf("RLIMIT_MSGQUEUE=%d", *z.Msgqueue))
	}
	if z.Nice != nil {
		a = append(a, fmt.Sprintf("RLIMIT_NICE=%d", *z.Nice))
	}
	if z.Nofile != nil {
		a = append(a, fmt.Sprintf("RLIMIT_NOFILE=%d", *z.Nofile))
	}
	if z.Nproc != nil {
		a = append(a, fmt.Sprintf("RLIMIT_NPROC=%d", *z.Nproc))
	}
	if z.Rss != nil {
		a = append(a, fmt.Sprintf("RLIMIT_RSS=%d", *z.Rss))
	}
	if z.Rtprio != nil {
		a = append(a, fmt.Sprintf("RLIMIT_RTPRIO=%d", *z.Rtprio))
	}
	if z.Sigpending != nil {
		a = append(a, fmt.Sprintf("RLIMIT_SIGPENDING=%d", *z.Sigpending))
	}
	if z.Stack != nil {
		a = append(a, fmt.Sprintf("RLIMIT_STACK=%d", *z.Stack))
	}

	return a
}
