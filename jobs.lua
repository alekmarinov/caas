local uv  = require "luv"

local _M = {
    jobs = {}
}

function _M.register(jobname, cmdline)
    if _M.jobs[jobname] then
        return nil, string.format("Job %s is already registered", jobname)
    end
    assert(type(cmdline) == "string")

    _M.jobs[jobname] = {
        name = jobname,
        cmdline = cmdline,
        instances = {}
    }
    return true
end

function _M.start(jobname, ondata)
    local job, err = _M.get(jobname)
    if not job then
        return nil, err
    end
    local instances = job.instances
    local instance = {
        datetime = os.date ("%Y-%m-%d %H:%M:%S"),
        running = false,
        log = {},
        listeners = {}
    }
    table.insert(instances, instance)

    local stdout = uv.new_pipe(false)
    local stderr = uv.new_pipe(false)
    instance.child, instance.pid = uv.spawn(job.cmdline, {
        stdio = {nil, stdout, stderr}
    }, function (code, signal) 
        uv.close(instance.child)
        instance.running = false
        instance.code = code
        instance.signal = signal
    end)
    if not instance.child then
        return nil, instance.pid
    end
    instance.running = true

    uv.read_start(stdout, function(err, data)
        assert(not err, err)
        if data then
            table.insert(instance.log, {data, nil})
        end
        if ondata then
            ondata(data)
        end
        for listener in pairs(instance.listeners) do
            listener(data, nil)
        end
    end)
    uv.read_start(stderr, function(err, data)
        assert(not err, err)
        if data then
            table.insert(instance.log, {nil, data})
        end
        if ondata then
            ondata(data)
        end
        for listener in pairs(instance.listeners) do
            listener(nil, data)
        end
    end)

    return #instances
end

function _M.stop(jobname, instid)
    local instance, err = _M.getinstance(jobname, instid)
    if not instance then
        return nil, err
    end
    if instance.running then
        if not instance.child then
            for i,v in pairs(instance) do print(i,v) end
            error("internal error")
        end
        uv.process_kill(instance.child)
    end
    return true
end

function _M.destroy(jobname)
    local job, err = _M.get(jobname)
    if not job then
        return nil, err
    end
    for _, instance in ipairs(job.instances) do
        if instance.running then
            return nil, string.format("Can't destroy %s while having running instances", jobname)
        end
    end
    _M.jobs[jobname] = nil
    return true
end

function _M.get(jobname)
    local job = _M.jobs[jobname]
    if not job then
        return nil, string.format("Job %s doesn't exists", jobname)
    end
    return job
end

function _M.getinstance(jobname, instid)
    if not _M.jobs[jobname] then
        return nil, string.format("Job %s doesn't exists", jobname)
    end
    local instances = _M.jobs[jobname].instances
    if not instid then
        return instances[#instances]
    end
    local instance = instances[instid]
    if not instance then
        return nil, string.format("Job %s have no instance %d", jobname, instid)
    end
    return instance
end

function _M.listen(jobname, instid, callback)
    local instance, err = _M.getinstance(jobname, instid)
    if not instance then
        return nil, err
    end
    instance.listeners[callback] = true
end

function _M.unlisten(jobname, instid, callback)
    local instance, err = _M.getinstance(jobname, instid)
    if not instance then
        return nil, err
    end
    instance.listeners[callback] = nil
end

return _M
