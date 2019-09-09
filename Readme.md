# CAAS (Command-As-A-Service)

Manages registration and execution of server side commands

## Example

```bash
# On one host
$cat test.sh
#!/bin/sh
for i in $(seq 1 100); do echo $i; sleep 1; done

$lua caas.lua
luvhttpd is listening on 0.0.0.0:8080

# On another host
$curl -d './test.sh' http://localhost:8080/job/test
Job test registered with command = './test.sh'

$curl -X POST http://localhost:8080/job/test
1
2
3
4
^C
$curl http://localhost:8080/job/test
test:1 running (./test.sh)
$curl http://localhost:8080/job/test/1
76
77
78
79
^C
$curl -X DELETE http://localhost:8080/job/test/1
Job test:1 has been stopped
$curl http://localhost:8080/job
test:1 finished (./test.sh)
$curl -X DELETE http://localhost:8080/job/test
Job test has been destroyed
```
