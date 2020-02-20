# CAAS (Command-As-A-Service)

API turning shell commands into API

## Environment variables

**CAAS_BASE_URI** - The base uri of the requests. Default empty string.
**CAAS_JOBS_DIR** - Directory where to store jobs persitantly. Default current server directory.

## Example

```bash
$lua caas.lua
caas 1.1.0 is listening on 0.0.0.0:8080

# On another host
$curl -d 'sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done"' http://localhost:8080/job/counter
Job counter registered with command = 'sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done"'

$curl -X POST http://localhost:8080/job/counter
1
2
3
4
^C
$curl http://localhost:8080/job/counter
2020-01-15 18:09:45 counter:1 running (sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done")
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
2020-01-15 18:09:45 counter:1 success, signal 15 (sh -c "for i in $(seq 1 100); do echo $i; sleep 1; done")

$curl -X DELETE http://localhost:8080/job/counter
Job counter has been destroyed
```

## Plugins

CAAS plugins can be loaded as given bellow:
```bash
caas --plugins plugin_name1,plugin_name2,...
```

CAAS plugin is a lua module under package *caas.plugin.foo*.
It can be loaded by the command bellow:
```bash
caas --plugins foo
```
If there are more than one plugins to be loaded they can be provided as a comma separated list of plugin names, e.g.:
```bash
caas --plugins foo,bar
```

### Prometheus plugin

Built-in plugin which enables Prometheus metrics for each job.
To enable the prometheus plugin start caas server as given bellow:
```bash
$lua caas.lua --plugins prometheus
caas 1.1.0 is listening on 0.0.0.0:8080
Loading plugin prometheus 1.0.0
```

For each job which Prometheus metrics will be exported create a file:
*$CAAS_JOBS_DIR/<job_name>.metrics/<metric_name>.gauge*

The .gauge file is text file holding Prometheus gauge data in the following format:
line1 - gauge value
line2 - gauge description
line3... - each next line have the format of label-name=label-value

The prometheus plugin will handle request to /metrics and will collect all data from all .metrics folders in $CAAS_JOBS_DIR and create prometheus gauge for each .gauge file. **Currently only gauge is supported.**

