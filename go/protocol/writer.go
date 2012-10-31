package protocol

import (
	"bufio"
	proto "code.google.com/p/goprotobuf/proto"
	"io"
	"strconv"
)

func writeMessage(w *bufio.Writer, m *Message) error {
	data, err := proto.Marshal(m)
	if err != nil {
		return err
	}

	line := strconv.Itoa(len(data))
	line += "\r\n"

	_, err = w.WriteString(line)
	if err != nil {
		return err
	}

	_, err = w.Write(data)
	if err != nil {
		return err
	}

	_, err = w.WriteString("\r\n")
	if err != nil {
		return err
	}

	return nil
}

type RequestWriter struct {
	w *bufio.Writer
}

func NewRequestWriter(w io.Writer) *RequestWriter {
	rw := &RequestWriter{}
	rw.w = bufio.NewWriter(w)
	return rw
}

func (rw *RequestWriter) Write(r Request) error {
	data, err := proto.Marshal(r)
	if err != nil {
		return err
	}

	t := r.Type()
	m := &Message{
		Type:    &t,
		Payload: data,
	}

	return writeMessage(rw.w, m)
}

type ResponseWriter struct {
	w *bufio.Writer
}

func NewResponseWriter(w io.Writer) *ResponseWriter {
	rw := &ResponseWriter{}
	rw.w = bufio.NewWriter(w)
	return rw
}

func (rw *ResponseWriter) Write(r Response) error {
	data, err := proto.Marshal(r)
	if err != nil {
		return err
	}

	t := r.Type()
	m := &Message{
		Type:    &t,
		Payload: data,
	}

	return writeMessage(rw.w, m)
}
