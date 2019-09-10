# CAAS (Command-As-A-Service)

Manages registration and execution of server side commands

## Example

```bash
$lua caas.lua
luvhttpd is listening on 0.0.0.0:8080

# On another host
$curl -d 'sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done"' http://localhost:8080/job/counter
Job test registered with command = 'sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done"'

$curl -X POST http://localhost:8080/job/counter
1
2
3
4
^C
$curl http://localhost:8080/job/counter
counter:1 running (sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done")
To see the result from the last instance try http://localhost:8080/job/counter/last

$curl http://localhost:8080/job/counter/1
...
76
77
78
79
^C
$curl -X DELETE http://localhost:8080/job/counter/1
Job counter:1 has been stopped

$curl http://localhost:8080/job
counter:1 finished (sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done")

$curl -X DELETE http://localhost:8080/job/counter
Job counter has been destroyed
```
