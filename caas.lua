local server = require "luvhttpd"
local jobs  = require "jobs"

local function handlepost(cb)
    return function(req, res)
        local postdata = {}
        req.ondata = function (data)
            if data then
                table.insert(postdata, data)
            else
                cb(req, res, table.concat(postdata))
            end
        end
    end
end

server.create()
    .handle("POST", "^/job/(.*)$", handlepost(function(req, res, command)
        local jobname = req.params[1]
        if command ~= "" then
            -- register command
            local ok, err = jobs.register(jobname, command)
            if ok then
                res.close(string.format("Job %s registered with command = '%s'\n", jobname, command))
            else
                res.close(err.."\n")
            end
        else
            -- execute command
            local ok, err = jobs.start(req.params[1], res.write)
            if not ok then
                res.close(err.."\n")
            end
        end
    end))
    .handle("DELETE", "^/job/(.*)/(.*)$", function(req, res)
        local jobname, instid = table.unpack(req.params)
        instid = tonumber(instid)
        local instance = jobs.getinstance(jobname, instid)
        local wasrunning = instance and instance.running
        local ok, err = jobs.stop(req.params[1], instid)
        if ok then
            res.close(wasrunning and string.format("Job %s:%d has been stopped\n", jobname, instid))
        else
            res.close(err.."\n")
        end
    end)
    .handle("DELETE", "^/job/(.*)$", function(req, res)
        local jobname = req.params[1]
        local ok, err = jobs.destroy(jobname)
        if ok then
            res.close(string.format("Job %s has been destroyed\n", jobname))
        else
            res.close(err.."\n")
        end
    end)
    .handle("GET", "^/job/(.-)/(.*)$", function(req, res)
        local jobname, instid = table.unpack(req.params)
        instid = tonumber(instid)
        local listencb
        listencb = function (outdata, errdata)
            local data = outdata or errdata
            res.write(data)
            if not data then
                jobs.unlisten(jobname, instid, listencb)
            end
        end
        res.onclose = function()
            jobs.unlisten(jobname, instid, listencb)
        end
        jobs.listen(jobname, instid, listencb)
    end)
    .handle("GET", "^/job/?(.*)$", function(req, res)
        local empty = true
        local jobname = req.params[1]
        for jname, job in pairs(jobs.jobs) do
            if jobname == "" or jname == jobname then
                empty = false
                if #job.instances > 0 then
                    for i, instance in ipairs(job.instances) do
                        res.write(string.format("%s:%d %s (%s)\n", jname, i, instance.running and "running" or "finished", job.cmdline))
                    end
                else
                    res.write(string.format("%s has no instances (%s)\n", jname, job.cmdline))
                end
            end
        end
        if empty then
            if jobname ~= "" then
                res.write(string.format("Job %s is not registered\n", jobname))
            else
                res.write("No registered jobs found\n")
            end
        end
        res.close()
    end)
.start()
