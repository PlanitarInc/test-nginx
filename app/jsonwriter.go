package main

import (
	"encoding/json"
	"net/http"

	"github.com/PlanitarInc/web"
)

type JsonWriter interface {
	SetObj(interface{}, int)
	SetError(string, int)
	Emit() error
}

type ErrorResponse struct {
	Error string `json:"error,omitempty"`
}

type simpleJsonWriter struct {
	rw         web.ResponseWriter
	statusCode int
	jsonObj    interface{}
}

func New(rw web.ResponseWriter) JsonWriter {
	jw := simpleJsonWriter{
		rw: rw,
	}
	return &jw
}

func (jw *simpleJsonWriter) SetObj(jsonObj interface{}, code int) {
	jw.jsonObj = jsonObj
	jw.statusCode = code
}

func (jw *simpleJsonWriter) SetError(err string, code int) {
	jw.SetObj(&ErrorResponse{Error: err}, code)
}

func (jw *simpleJsonWriter) Emit() error {
	if jw.statusCode == 0 {
		jw.statusCode = http.StatusOK
	}

	jw.rw.Header().Set("Content-Type", "application/json")
	jw.rw.WriteHeader(jw.statusCode)
	if jw.jsonObj == nil {
		return nil
	}
	return json.NewEncoder(jw.rw).Encode(jw.jsonObj)
}
