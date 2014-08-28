package main

import (
	"database/sql"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"

	"github.com/PlanitarInc/context"
	"github.com/PlanitarInc/sessions"
	"github.com/PlanitarInc/web"
	_ "github.com/lib/pq"
	"github.com/rlmcpherson/s3gof3r"
)

var (
	sessionid = "SID"
	hashKey   = []byte("k_F3X5@H#pJbHmJlhN)^440&fQE&w1!1")
	blockKey  = []byte("lhdar^-n*pMkraUJoPYWV6^XfCJF$D4$")
	store     = sessions.NewCookieStore(hashKey, blockKey)

	db *sql.DB
)

type baseCtx struct{}

type apiCtx struct {
	*baseCtx
	replier  JsonWriter
	sessions map[string]*sessions.Session
}

func (ctx *baseCtx) contextClear(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	fmt.Printf("%s %s\n", req.Method, req.URL.Path)
	next(rw, req)
	/* XXX Gorilla's sessions use global `context`, need to clean it manually. */
	context.Clear(req.Request)
	fmt.Println("")
}

func (ctx *apiCtx) setSessions(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	ctx.sessions = make(map[string]*sessions.Session)

	next(rw, req)

	/* XXX Clean? */
	ctx.sessions = make(map[string]*sessions.Session)
}

func (ctx *apiCtx) setJsonWriter(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	ctx.replier = New(rw)

	next(rw, req)

	fmt.Println("emitting..............")
	ctx.replier.Emit()
}

func (ctx *apiCtx) getSession(name string, rw web.ResponseWriter, req *web.Request) *sessions.Session {
	if session, ok := ctx.sessions[name]; ok {
		fmt.Printf("session: session '%s' is alread loaded\n", name)
		return session
	}

	session, err := store.Get(req.Request, name)
	if err != nil {
		fmt.Printf("session: sessionid get error: %s\n", err)
		return session
	}
	fmt.Printf("load session: %v\n", session)
	ctx.sessions[name] = session
	return session
}

func (ctx *apiCtx) removeSession(name string, rw web.ResponseWriter, req *web.Request) {
	session, ok := ctx.sessions[name]
	if !ok {
		fmt.Printf("cannot find session: %s\n", name)
		return
	}

	fmt.Printf("remove session: %v\n", session)
	/* Remove all values and invalidate the cookie */
	session.Values = make(map[interface{}]interface{})
	session.Options.MaxAge = -1
}

func (ctx *apiCtx) saveSession(name string, rw web.ResponseWriter, req *web.Request) {
	session, ok := ctx.sessions[name]
	if !ok {
		fmt.Printf("cannot find session: %s\n", name)
		return
	}

	fmt.Printf("save session: %v\n", session)
	if err := session.Save(req.Request, rw); err != nil {
		fmt.Printf("cannot save session: %s\n", err)
	}
}

type viewCtx struct {
	*apiCtx
	viewId string
}

func (ctx *viewCtx) loadSession(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	ctx.getSession("qwe", rw, req)
	next(rw, req)
	ctx.saveSession("qwe", rw, req)
}

func (ctx *viewCtx) authenticated(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	fmt.Printf("authenticating... ")
	/* XXX send some query, wait for the response, we don't really care what
	 * the reponse is.
	 */
	var s sql.NullString
	if err := db.QueryRow(`SELECT pg_sleep(0.1)`).Scan(&s); err != nil {
		fmt.Println("FAILED:", err)
		ctx.replier.SetError(err.Error(), http.StatusInternalServerError)
		return
	}

	fmt.Println("OK")
	next(rw, req)
}

func (ctx *viewCtx) authorized(rw web.ResponseWriter, req *web.Request, next web.NextMiddlewareFunc) {
	fmt.Printf("checking permissions... ")

	if _, ok := req.PathParams["key"]; !ok {
		fmt.Println("FAILED:", err)
		ctx.replier.SetError("could not find key", http.StatusInternalServerError)
		return
	}

	fmt.Println("OK")
	next(rw, req)
}

func (ctx *viewCtx) get(rw web.ResponseWriter, req *web.Request) {
	key, _ := req.PathParams["key"]

	fmt.Printf("trying to get '%s'... ", key)

	if err := getS3Object(key, rw); err != nil {
		fmt.Println("FAILED:", err)
		ctx.replier.SetError(err.Error(), http.StatusInternalServerError)
		return
	}

	fmt.Println("OK")
	ctx.replier.SetObj(nil, 200)
}

func getS3Object(key string, rw web.ResponseWriter) error {
	conf := new(s3gof3r.Config)
	*conf = *s3gof3r.DefaultConfig
	conf.Md5Check = false

	k, err := s3gof3r.EnvKeys()
	if err != nil {
		return err
	}

	s3 := s3gof3r.New("", k)
	b := s3.Bucket(os.Getenv("AWS_S3_BUCKET"))

	s3gof3r.SetLogger(os.Stderr, "", log.LstdFlags, true)

	r, header, err := b.GetReader(key, conf)
	if err != nil {
		return err
	}
	log.Println("Headers: ", header)
	if _, err = io.Copy(rw, r); err != nil {
		return err
	}
	if err = r.Close(); err != nil {
		return err
	}
	return nil
}

func main() {
	router := web.New(baseCtx{})
	router.Middleware((*baseCtx).contextClear)

	router.Middleware(web.StaticMiddleware("static"))

	apiRouter := router.Subrouter(apiCtx{}, "/api/v1")
	/* This is a little bit unexpected, but the order of middleware invocation
	 * is the opposite of the order of middleware definition. Hence
	 * Session middleware should come before the Json Writer middleware,
	 * because session cookies are to be set before anything is emitted.
	 */
	apiRouter.Middleware((*apiCtx).setSessions)
	apiRouter.Middleware((*apiCtx).setJsonWriter)

	/* Configure the endpoints */
	viewRouter := apiRouter.Subrouter(viewCtx{}, "/view")
	viewRouter.Middleware((*viewCtx).loadSession)
	viewRouter.Middleware((*viewCtx).authenticated)
	viewRouter.Middleware((*viewCtx).authorized)
	viewRouter.Get(":key", (*viewCtx).get)

	/* Connect to DB */
	var err error
	db, err = sql.Open("postgres", "dbname=iguidedb host=localhost user=view_api")
	if err != nil {
		panic(err)
	}

	http.ListenAndServe(":9000", router)
}
