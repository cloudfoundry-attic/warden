package protocol

import (
	"bufio"
	"code.google.com/p/goprotobuf/proto"
	"io"
	"strconv"
)

type Writer struct {
	*bufio.Writer
}

func NewWriter(w_ io.Writer) *Writer {
	w := &Writer{}
	w.Writer = bufio.NewWriter(w_)
	return w
}

func (w *Writer) WriteMessage(m *Message) error {
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

func (w *Writer) WriteRequest(r Request) error {
	data, err := proto.Marshal(r)
	if err != nil {
		return err
	}

	t := r.Type()
	m := &Message{
		Type:    &t,
		Payload: data,
	}

	return w.WriteMessage(m)
}

func (w *Writer) WriteResponse(r Response) error {
	data, err := proto.Marshal(r)
	if err != nil {
		return err
	}

	t := r.Type()
	m := &Message{
		Type:    &t,
		Payload: data,
	}

	return w.WriteMessage(m)
}
