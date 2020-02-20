local lfs = require "lfs"

local function trim(s)
    return s:match'^%s*(.*%S)' or ''
end

local function normalizedir(dir)
    if not dir then
        return nil
    end
    if dir:sub(-1) ~= "/" then
        dir = dir.."/"
    end
    return dir
end

local _M = {
    jobext = "caas",
    jobsdir = nil
}

function _M.getjobfile(filename)
    return _M.jobsdir..filename
end

function _M.init(jobsdir)
    _M.jobsdir = normalizedir(jobsdir)

    -- Naive create directory
    lfs.mkdir(_M.jobsdir)
end

function _M.loadjobs()
    local jobs = {}
    for file in lfs.dir(_M.jobsdir) do
        if file:sub(-1-_M.jobext:len()) == ".".._M.jobext then
            local fd, cmdline, err
            local jobname = file:sub(1, -6)
            local jobfile = _M.jobsdir..file
            fd, err = io.open(jobfile)
            if not fd then
                return nil, err
            end
            cmdline, err = fd:read("*a")
            if not cmdline then
                fd:close()
                return nil, err
            end
            fd:close()
            cmdline = trim(cmdline)
            jobs[jobname] = cmdline
        end
    end
    return jobs
end

function _M.savejob(jobname, cmdline)
    local jobfile, ok, fd, err
    jobfile, err = _M.getjobfile(jobname..".".._M.jobext)
    if not jobfile then
        return nil, err
    end
    fd, err = io.open(jobfile, "w")
    if not fd then
        return nil, err
    end
    ok, err = fd:write(cmdline.."\n")
    fd:close()
    if not ok then
        return nil, err
    end
    return jobfile
end

function _M.deletejob(jobname)
    local jobfile, err = _M.getjobfile(jobname..".".._M.jobext)
    if not jobfile then
        return nil, err
    end
    os.remove(jobfile)
end

return _M
