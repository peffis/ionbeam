# ionbeam

## Introduction
Ionbeam is a utility to run tests against HTTP servers. Its primary
focus is functionality testing and not performance testing. You write
test suits and run them against your servers while validating the
output in the responses.

## Building

```bash
$ make
```

## Running

Run the release like so

```bash
$ _rel/ionbeam/bin/ionbeam console
Eshell V9.1.2  (abort with ^G)
(ionbeam@127.0.0.1)1>
```

Just starting it does not do anything though. You need to write your
test module and put it in the src folder before you build. Then invoke
your test module's test function.

Example:

```
Eshell V9.1.2  (abort with ^G)
(ionbeam@127.0.0.1)1> tester:run().
11:31:47.017 [info]    running "Authenticating/logging in"
11:31:47.017 [info]      request: POST http://localhost:80/api/login
ok
(ionbeam@127.0.0.1)2>
```


## Writing tests

Tests consist of tasks. Each task is defined by an Erlang map that
describes what server to make the request against, what request path
to use, what headers to use and what body to use. The task also
defines the constraints you put on the response from the server - what
you expect from the server - regarding returned response code,
returned headers and returned body.

All fields in a task, such as the headers or the body, can include
variables, so think of the fields as templates that are to be filled
in. The values for the variables will be taken from the _input
context_ of the task and running a task and getting a response will
produce an _output context_ that can then be fed into the next task to
be executed. For each task, you define what values to extract from the
responses and how to use values in the input context to form the
request.

### Defining tasks
A task is defined as an Erlang map that has fields such as
description, method, host, path, body, statusConstraints,
headersConstraints and bodyConstraints.  All these fields have default
values (defined in
[ionbeam_task.erl](https://github.com/peffis/ionbeam/blob/170a24857e9762bfa4c601d17c2109ad4fb6879b/src/ionbeam_task.erl#L6-L17))
so if you are not interested in what headers or body are returned from
the server you can skip specifying the headersConstraints and the
bodyConstraints, and so on.

Example:

```erlang
    LoginTask = #{
      %% definitions
      description => "POST /api/login",
      method => "POST",
      host => "localhost",
      headers => "Accept: application/json\r\nContent-Type: application/json\r\n\r\n",
      path => "/api/login",
      body => "{\"email\":\"$(USER_NAME)\",\"password\":\"$(PASSWORD)\"}",

      %% constraints
      statusConstraints => [200],
      headersConstraints => #{
        matchHeaders => ["Content-Type: $(_CONTENT_TYPE)"],
        "_CONTENT_TYPE" => "application/json"
       },
      bodyConstraints => #{
        matchBody => "$(_A)\"token\":\"$(TOKEN)\"$(_C)"
       }
     },
```

In the example above you can see for instance that the body field
includes variables such as USER_NAME and PASSWORD. Variables in fields
that define the task (description, method, host, headers, path and
body) must all be present and have a value in the _input context_ when
you run this task or else  the task will fail.

There can be variables also in the constraints fields of a task (in the
example above there is a TOKEN variable present in the bodyConstraints
field and a _CONTENT_TYPE variable in the headersConstraints field). These variables
will be matched against the actual response from the server and bound to
values stored in the _output context_. Running the login task above
will extract the TOKEN value out of the response body, the content
type out of the response headers and put both these values in the
output context (iff the response matches the supplied constraints that
is).

To enforce that a value extracted from a respone must have a certain
value you add the specific value to the constraints object. See, for
instance, in the example, how the _CONTENT_TYPE variable is enforced
to be "application/json" in the respone or else the task will fail.

By default a value can only be bound once in a context. So if you try
to bind a value, such as TOKEN, and it already exists in the context
with a different value the match will fail. If you are not interested
in comparing values between tasks and still would like to reuse the
variable name you can prefix the variable name with an underscore
(such as in the example for _CONTENT_TYPE). This would mean that the
variable will not be brought over to the next task and will not cause
that task to fail if that task comes up with a different value for the
variable name.

### Putting tasks together into scripts

In order to run your tasks one after the other, you put together the
tasks in a _script_ which is an Erlang list of tasks with
their input and output contexts. Example:

```erlang
ionbeam:run_script([
                        %% do login
                        {LoginTask, #{"USER_NAME" => "alice",
                                      "PASSWORD" => "secret"}, 'LoginCtx'},

                        %% do list items
                        {ListItemsTask, 'LoginCtx', 'ListItemsCtx'}
                  ])
```

The contexts are referred to through its name. In the above
example, the output context of the LoginTask task is named 'LoginCtx'
which is fed in as an input context to ListItemsTask. The input
context can be specified either as a map, the atom '_'
(which means 'the empty context'), the name (as an Erlang atom) of an
existing context or you could specify it as a function that takes a map as
argument - a map containing
all previously created contexts. The latter option may be used if you would like to programmatically
merge many different contexts together into one, or create a
context from other sources.


To continue the example above, let us define the ListItemsTask as
well:

```erlang
    ListItemsTask = #{
      description => "GET /api/items",
      host => "localhost",
      headers => "Accept: application/json\r\nX-Token: $(TOKEN)\r\n\r\n",
      path => "/api/items",
      headersConstraints => #{
        matchHeaders => ["Content-Type: $(_CONTENT_TYPE)"],
        "_CONTENT_TYPE" => "application/json"
       },
      bodyConstraints => #{
        matchBody => "$(_BODY)"
       }
     }
```

As you can see, this pretended HTTP API needs an authentication
header <i>X-Token</i> with a token value, which is the value
returned from the login request above. We therefore give the output
context from the LoginTask task as input context to the ListItemsTask
task. We don't do much validation for this task except for the status
code which, since we did not say anything, must be 200 and the
Content-Type value must be "application/json".

The automatic matching of variables is done using the [template
library](https://github.com/peffis/template) which is fine, generic
and all, but for very large bodies of data it might not be that
impressive when it comes to performance. It could also be that you
would like to programmatically parse and extract certain information
that cannot be described using the template matcher so therefore it is
possible to, instead of using matchBody, set bodyConstraints to be an _erlang fun_ that
vill validate the body instead. This function takes two arguments -
the body and the current context - and you can then parse the body in
whatever way you like and return a new context (or return an error
tuple - {error, "some reason"} - if you do not think the body is
correct). As an example, say that the body returned is a json document
and you which you know should have a field "members" which is a list
and you want to check if "stefan" is a member of that list. The
resulting body validation fun, if we use jiffy for json parsing, could
then look something like like:

```erlang
        ...
        bodyConstraints =>
              fun(Body, Ctx) ->
                      #{<<"members">> := Members} = jiffy:decode(Body, [return_maps]),
                      case lists:member(<<"stefan">>, Members) of
                          true ->
                              Ctx;
                          _ ->
                              {error, "stefan must be a member, but was not"}
                      end
              end
```