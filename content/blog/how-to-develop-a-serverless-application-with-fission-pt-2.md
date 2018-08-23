+++
type = "post"
author = "ta-ching chen"
title = "How to Develop a Serverless Application with Fission (Part 2)"
description = ""
spliter = " | "
categories = [""]
tags = [""]
keywords = ""
date = "2018-08-07T16:48:12+08:00"

draft = true

images = ["/img/fission-and-istio-integration/fission.min.png"]
featured = "fission.min.png"
featuredpath = "/img/fission-and-istio-integration"
featuredalt = ""
linktitle = ""
+++

# Introduction

At [Part 1](/blog/how-to-develop-a-serverless-application-with-fission-pt-1), we talked about the advantage of adopting fission as serverless framework on 
kubernetes, basic concept of around fission core and how to create a simple HelloWorld example with fission.

In this post we'll dive deeper to see what's the payload of a HTTP request will be passed into user function 
and learn how to create a serverless guestbook consists with REST functions in Golang.

# How Fission maps HTTP requests to user function

Before we diving into code, we first need to understand what exactly happened inside Fission. Here is a brief diagram describes how requests being sent to function inside Kubernetes cluster.

![router maps req to fn](/img/how-to-develop-a-serverless-application-with-fission/router-maps-request-to-fn.svg)

The requests will first come to the `router` and it checks whether the destination `URL` and `HTTP method` are registered by `http trigger`. 
Once both are matched, router will then proxy request to the function pod (a pod specialized with function pointed by http trigger) to get response from it; reject, otherwise.

# What's Content of Request Payload 

Now, we know how a request being proxied the user function, there are some questions you might want to ask:

1. Will `router` modify http request?
2. What's the payload will be passed to function?

To answer these questions, let's create a python function that returns HTTP `Header`, `Query String` and `Message Body`
to see what's inside of a request sent to user function.

* requestdata.py
  
```python
from flask import request
from flask import current_app

def main():
    current_app.logger.info("Received request")
    msg = "\n---HEADERS---\n%s\n---QUERY STRING---\n%s\n\n--BODY--\n%s\n-----\n" % (request.headers, request.query_string, request.get_data())
    return msg
```

```bash
$ fission env create --name pythonv1 --image fission/python-env:0.9.2 --version 1 --period 5

# With flag --method and --url, we can create a function and a HTTP trigger at the same time. 
$ fission fn create --name reqpayload --env pythonv1 \
    --code requestdata.py --method POST --url "/test/{foobar}"

$ curl -X POST -d '{"test": "foo"}' \
    -H "Content-Type: application/json" \
    "http://${FISSION_ROUTER}/test/pathvar?foo=bar"
```

*NOTE: For how to set up `$FISSION_ROUTER`, please visit http://localhost:51405/0.9.2/usage/trigger/*

## Request Payload

```html
---HEADERS---
Accept-Encoding: gzip
Host: 172.17.0.25:8888
Connection: close
Accept: */*
User-Agent: curl/7.54.0
Content-Length: 15
Content-Type: application/json
X-Forwarded-For: 172.17.0.1
X-Fission-Function-Uid: 82c95606-9afa-11e8-bbd1-08002720b796
X-Fission-Function-Resourceversion: 480652
X-Fission-Function-Name: reqpayload
X-Fission-Function-Namespace: default
X-Fission-Params-Foobar: pathvar

---QUERY STRING---
b'foo=bar'

--BODY--
b'{"test": "foo"}'
-----
```

As you can see, the router leaves `query string` and `body` parts intact, so you can access the value as usual. 

On the other hand, some `header` fields was changed/add to the payload, following we will explain where the value/fields came from.

**Fields Changed**

* `Host`: Originally, the host is address to the fission router. The value was replaced with the address of function pod or the kubernetes service address of function.

* `X-Forwarded-For`: The address of docker network interface was added during proxy stage.

**Fields Added**

* `X-Fission-Function-*`: The metadata of function that processing the request.

* `X-Fission-Params-*`: The path parameters specified in http trigger url. One thing worth to notice is that the name of parameter will be convert to a form with upper case of first character and lower case for the rest. For example, `{foobar}` in `"/test/{foobar}"` will be converted and added to request header with header key `X-Fission-Params-Foobar`.

# A Serverless Guestbook Application in Golang (Sample)

In this section, we use a simple guestbook to explain how to create a serverless application.

![router maps req to fn](/img/how-to-develop-a-serverless-application-with-fission/guestbook-diagram.svg)

The guestbook is composed with four REST APIs and each API consist of a function and a HTTP trigger.  

## Installation

You can clone repo below and follow the guide to install/try guestbook sample.

* [Fission REST API Repo](https://github.com/fission/fission-restapi-sample)

<!--## Create a function in Golang

Golang added [plugin](https://golang.org/pkg/plugin/) package since 1.8, it allows a program to load plugin file dynamically. 

Here is a hello world example in Golang:  

```go
// Due to golang plugin mechanism,
// the package of function handler must be main package
package main

import (
    "net/http"
)

// Handler is the entry point for this fission function
func Handler(w http.ResponseWriter, r *http.Request) {
    msg := "Hello, world!\n"
    w.Write([]byte(msg))
}
```

You can create & test with commands:

```bash
# Create golang env with builder image to build go plugin
$ fission env create --name go --image fission/go-env --builder fission/go-builder

$ fission fn create --name helloworld --env go --src hw.go --entrypoint Handler
```

There are two interesting flags when creating the function: `--src` and `--entrypoint`.

* `--src` is the source file of a function. Normally, it will be a `ZIP` file, with Golang env you can use a single file as well.
* `--entrypoint` let server know which function to run with. In Go, the value of entrypoint is simply the function name.

After creating the function, a fission component call `buildermgr` will help us to build go source code into plugin file.
You can check the build status & logs with following commands:

```bash
$ fission pkg list
NAME                     BUILD_STATUS ENV
hello-go-llux            succeeded    go

$ fission pkg info --name hello-go-llux
Name:        hello-go-llux
Environment: go
Status:      succeeded
Build Logs:
Building file /packages/a-go-llux-nsjtzw in /tmp/a-go-llux-nsjtzw
```

Once the status change from `running` succeeded, we can test function with built-in test command.

```bash
$ fission fn test --name helloworld
```

## Add Additional Go Dependencies

Though we already demonstrate how to create a function with single Go file, we often write a Go application with third-party 
dependencies in real world. To support this, here are couple steps to follow with:

1. Download all necessary dependencies to `vendor` directory
2. Archive all go files (include dependencies)
3. Create function with ZIP file just created

Let's use [vendor-example](https://github.com/fission/fission/tree/master/examples/go/vendor-example) as demonstration. The structure of `vendor-example` looks like this
```bash
vendor-example/
├── main.go
└── vendor
    └── github.com
        └── ......
```

You can use popular Go dependency management tool like `dep` and `glide` to download all dependencies to `vendor` directory. 
Since `vendor-example` is the root directory of user function, we should ignore it when archive function files. Otherwise,
the function builder will not be able to find Go files to built with.    

```bash
$ cd ${GOPATH}/src/github.com/fission/fission/examples/go/vendor-example/

# Only archive the files under vendor-example, 
# otherwise go builder will not be able to build plugin
$ zip -r example.zip .

$ fission fn create --name foobar --env go --src example.zip --entrypoint Handler

$ fission fn test --name foobar
```
-->

## Create Fission Objects for REST API

A REST API uses HTTP method to determine what's the action server needs to perform on resource(s) represents in the URL. 

```bash
POST   http://api.example.com/user-management/users/{id}
PUT    http://api.example.com/user-management/users/{id}
GET    http://api.example.com/user-management/users/{id}
DELETE http://api.example.com/user-management/users/{id}
```

To create a REST API with fission, we need to create following things to make it work:

* `HTTP Trigger` with specific HTTP method and URL contains the resource type we want manipulate with.
* `Function` to handle the HTTP request.

### HTTP Trigger

At part1, you can create a HTTP trigger with command

```bash
$ fission httptrigger create --method GET --url "/my-first-function" --function hello
```

There are 3 important elements in the command:

* `method`: The HTTP method of REST API
* `url`: The API URL contains the resource placeholder
* `function`: The function reference to a fission function

As a real world REST API, the URL would be more complex and contains the resource placeholder. To support such use cases, you can change URL to something like following:

```bash
$ fission httptrigger create --method GET \
    --url "/guestbook/messages/{id}" --function restapi-get
```

Since fission uses `gorilla/mux` as underlying URL router, you can write regular expression in URL to filter out illegal API requests.

* [route-29c87b8b-ffc1-4a13-bb1c-87f66367474a.yaml](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/specs/route-29c87b8b-ffc1-4a13-bb1c-87f66367474a.yaml#L14)

```bash
$ fission httptrigger create --method GET \
    --url "/guestbook/messages/{id:[0-9]+}" --function restapi-get
```

### Function

To handle a REST API request, normally a function need to extract resource from the request URL. 
In fission you can get the resource value from request header directly as we described in [Request Payload](/blog/how-to-develop-a-serverless-application-with-fission-pt-2/#request-payload).

That means you can get value from header with key `X-Fission-Params-Id` if URL is `/guestbook/messages/{id}`.

In Golang you can use `CanonicalMIMEHeaderKey` to transform letter case. 

* [rest-api/api.go](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/rest-api/api.go#L39-L57) 

```go
import (
    "net/textproto"
)

const (
    URL_PARAMS_PREFIX = "X-Fission-Params"
)

func GetPathValue(r *http.Request, param string) string {
    // transform text case
    // For example: 'id' -> 'Id', 'fooBAR' -> 'Foobar', 'foo-BAR' -> 'Foo-Bar'.
    param = textproto.CanonicalMIMEHeaderKey(param)

    // generate header key for accessing request header value
    key := fmt.Sprintf("%s-%s", URL_PARAMS_PREFIX, param)

    // get header value
    return r.Header.Get(key)
}
```

When Golang server receive HTTP requests, it dispatches `entrypoint function` and passes whole `response writer` and `request` object to the function.

```go
func MessageGetHandler(w http.ResponseWriter, r *http.Request) {
    ...
}
```

In this way, you can access `query string` and `message body` as usual. 

* [rest-api/api.go](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/rest-api/api.go#L65-L67)

```go
func GetQueryString(r *http.Request, query string) string {
    return r.URL.Query().Get(query)
}
```

* [rest-api/api.go](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/rest-api/api.go#L103-L110)

```go
body, err := ioutil.ReadAll(r.Body)
if err != nil {
    err = errors.Wrap(err, "Error reading request body")
    log.Println(err.Error())
    w.WriteHeader(http.StatusBadRequest)
    w.Write([]byte(err.Error()))
    return
}
```

## Access Third-Party Service in Function 

In guestbook application we need to store messages in database. Since fission is build on top of kubernetes, 
it's very easy to achieve this by creating Kubernetes `Service(svc)` and `Deployment` let function to access with.

![Access 3rd service](/img/how-to-develop-a-serverless-application-with-fission/access-3rd-service.svg)

* [cockroachdb.yaml](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/cockroachdb.yaml)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: cockroachdb
  namespace: guestbook
spec:
  selector:
    name:  cockroachdb
    service: database
  type:  ClusterIP
  ports:
  - name: db
    port: 26257
    targetPort:  26257
  - name: dashboard
    port: 8080
    targetPort: 8080
```

In [cockroachdb.yaml](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/cockroachdb.yaml), 
we create a deployment and service for CockroachDB. After the creation, the function can access the service with DNS name `<service>.<namespace>:<port>`. 
In this case, the DNS name will be `cockroachdb.guestbook:26257`.

* [rest-api/api.go](https://github.com/fission/fission-restapi-sample/blob/4398eb195aeb59523101aa68a62782d91f86d85a/rest-api/api.go#L29)

```go
dbUrl := "postgresql://root@cockroachdb.guestbook:26257/guestbook?sslmode=disable"
```  

# Deploy the Same Application to Different Environment

We may have different environments (e.g. Canary, Production) to test and run with. Fission allows users to deploy the same
application with `spec` files. A spec file is a Fission Object in YAML format includes all necessary information. 

Here is a sample YAML that describe a go environment:

```yaml
apiVersion: fission.io/v1
kind: Environment
metadata:
  creationTimestamp: null
  name: go
  namespace: default
spec:
  TerminationGracePeriod: 360
  builder:
    command: build
    image: fission/go-builder
  keeparchive: false
  poolsize: 3
  resources: {}
  runtime:
    functionendpointport: 0
    image: fission/go-env
    loadendpointpath: ""
    loadendpointport: 0
  version: 2
```

Another good news is you don't need to write YAML files by hand. Here are steps for how to create spec files:

1. Create spec directory
2. Create fission resources with flag `--sepc`
3. Check spec files under `spec` directory

```bash
$ fission spec init

$ fission env create --name go --image fission/go-env --builder fission/go-builder --spec

$ cat specs/env-go.yaml
```

After creating fission resources for application, you can deploy & destroy an application with `fission spec` command:

```bash
$ fission spec apply 
```

Now, the go environment was created automatically.

```bash
$ fission env list
NAME   UID                                  IMAGE            POOLSIZE MINCPU MAXCPU MINMEMORY MAXMEMORY EXTNET GRACETIME
go     d30a78ee-a618-11e8-a55e-08002720b796 fission/go-env   3        0      0      0         0         false  360
```

Once the application is no longer needed, use `destroy` to remove it.

```bash
$ fission spec destroy
```
