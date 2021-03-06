local lfs = require "lfs"
local server = require "caas.luvhttpd"
local jobs  = require "caas.jobs"

server._SERVER_SOFTWARE = "caas"
server._VERSION = "1.3.2"
server._BASE_URI = os.getenv("CAAS_BASE_URI") or ""

caas = setmetatable({}, { __index = server })
local unpack = unpack or table.unpack

local function usage()
    print(string.format("%s %s", caas._SERVER_SOFTWARE, caas._VERSION))
    print(string.format(
        "Usage:\n\t%s [--plugins PLUGINS]\n"..
        "Where:\n"..
        "\tPLUGINS  - Comma separated list of plugin NAMEs causing a module 'caas-plugin-NAME' to be loaded"
        , arg[0]))
    os.exit(1)
end

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

local function mkpath(...)
    local args = {...}
    for i = 1, #args do
        if args[i]:sub(-1) == "/" then
            args[i] = args[i]:sub(1, -2)
        end
    end
    return table.concat(args, "/")
end

local function execout(cmd)
    local f = assert(io.popen(cmd, 'r'))
    local s = assert(f:read('*a'))
    f:close()
    s = string.gsub(s, '^%s+', '')
    s = string.gsub(s, '%s+$', '')
    s = string.gsub(s, '[\n\r]+', ' ')
    return s
end

local function handledir(req, res)
    local filename = req.params[1]
    if filename:sub(1, 1) ~= "/" then
        filename = "/"..filename
    end
    local attr, err = lfs.attributes(filename)
    if not attr then
        return caas.err_404(req, res)
    end
    if attr.mode == "file" then
        local out = execout("file \""..filename:gsub("\"", "\\\"").."\"")
        local chunked = false
        if out:find("ASCII text") then
            res.headers["content-type"] = "text/plain"
        else
            local basename = string.gsub(filename, "(.*/)(.*)", "%2")
            res.headers["content-disposition"] = string.format("attachment; filename=\"%s\"", basename)
            res.headers["content-type"] = "application/octet-stream"
            res.headers["transfer-encoding"] = "chunked"
            chunked = true
        end
        res.headers["content-length"] = string.format("%d", attr.size)
        local fd = io.open(filename, "rb")
        local bufsize = 1024*1024
        local buf = fd:read(bufsize)
        while buf do
            if chunked then
                res.write(string.format("%X\r\n", buf:len()))
            end
            res.write(buf)
            if chunked then
                res.write("\r\n")
            end
            buf = fd:read(bufsize)
        end
        fd:close()
        if chunked then
            res.close(string.format("0\r\n\r\n"))
        else
            res.close()
        end
    elseif attr.mode == "directory" then
        if filename:sub(-1) ~= "/" then
            filename = filename.."/"
        end
        res.headers["content-type"] = "text/html"
        res.write("<body>\n")
        res.write(string.format("<p>Directory of %s:</p>\n", filename))
        res.write("    <table>\n")
        res.write("        <tr><td>permissions</td><td>change</td><td>modification</td><td>size</td><td>name</td></tr>\n")
        local files, dirs = {}, {}
        for file in lfs.dir(filename) do
            if file:sub(1,1) ~= "." then
                local fullname = mkpath(filename, file)
                local attr = lfs.attributes(fullname)
                if attr then
                    attr.name = file
                    if attr.mode == "directory" then
                        table.insert(dirs, attr)
                    elseif attr.mode == "file" then
                        table.insert(files, attr)
                    end
                end
            end
        end
        local function sendentry(attr)
            res.write(string.format("        <tr><td>%s</td><td>%s</td><td>%s</td><td>%d</td><td>", 
                attr.permissions,
                os.date("%x %X", attr.change),
                os.date("%x %X", attr.modification),
                attr.size
            ))
            res.write(string.format("<a href='%s/dir%s%s", server._BASE_URI, filename, attr.name))
            if attr.mode == "directory" then
                res.write("/")
            end
            res.write("'>")
            res.write(attr.name)
            if attr.mode == "directory" then
                res.write("/")
            end
            res.write("</a></td></tr>\n")
        end
        local entrycomparer = function (e1, e2) 
            return e1.name < e2.name
        end
        table.sort(dirs, entrycomparer)
        local parent = lfs.attributes(mkpath(filename, ".."))
        parent.name = ".."
        table.insert(dirs, 1, parent)
        table.sort(files, entrycomparer)
        for _, entry in ipairs(dirs) do
            sendentry(entry)
        end
        for _, entry in ipairs(files) do
            sendentry(entry)
        end
        res.write([[
</table>
</body>
]])
        res.close()
    else
        return caas.err_404(req, res)
    end
end

local handlepostjob = handlepost(function(req, res, command)
    local jobname = req.params[1] or ""
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
        local ok, err = jobs.start(jobname, res.write)
        if not ok then
            res.close(err.."\n")
        end
    end
end)

local function handleheadjob(req, res)
    local jobname = req.params[1] or ""
    if jobname ~= "" and not jobs.get(jobname) then
        -- requested job not found
        caas.err_404(req, res)
    else
        res.close()
    end
end

local function handledeleteinstance(req, res)
    local jobname, instid = unpack(req.params)
    instid = tonumber(instid)
    local instance = jobs.getinstance(jobname, instid)
    local wasrunning = instance and instance.running
    local ok, err = jobs.stop(req.params[1], instid)
    if ok then
        res.close(wasrunning and string.format("Job %s:%d has been stopped\n", jobname, instid))
    else
        res.close(err.."\n")
    end
end

function handledeletejob(req, res)
    local jobname = req.params[1]
    local ok, err = jobs.destroy(jobname)
    if ok then
        res.close(string.format("Job %s has been destroyed\n", jobname))
    else
        res.close(err.."\n")
    end
end

function handlegetinstance(req, res)
    local jobname, instid = unpack(req.params)
    local job, err = jobs.get(jobname)
    if not job then
        res.close(err.."\n")
        return
    end
    if string.lower(instid) == "last" then
        instid = #job.instances
    else
        instid = tonumber(instid)
    end
    local instance, err = jobs.getinstance(jobname, instid)
    if not instance then
        res.close(err.."\n")
        return
    end
    for _, line in ipairs(instance.log) do
        res.write(line[1] or line[2])
    end
    if not instance.running then
        res.close()
    end
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
end

function handlegetjob(req, res)
    local empty = true
    local jobname = req.params[1]
    for jname, job in pairs(jobs.jobs) do
        if jobname == "" or jname == jobname then
            empty = false
            if #job.instances > 0 then
                for i, instance in ipairs(job.instances) do
                    res.write(string.format("%s %s:%d %s (%s)\n", instance.datetime, jname, i, instance.running and "running" or (instance.code == 0 and ("success"..(instance.signal > 0 and ", signal "..instance.signal or "")) or "error "..(instance.code or "")), job.cmdline))
                end
                if jobname ~= "" then
                    res.write(string.format("To see the result from the last instance try http://%s:%s/job/%s/last\n", req.host or "host", req.port or "port", jobname))
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
end

-- entry point

-- process program arguments
local pluginsnames = {}
for i = 1, #arg do
    if arg[i] == '--help' or arg[i] == '-h' then
        usage()
    elseif arg[i] == '--plugins' or arg[i] == '-p' then
        i = i + 1
        local plugins = arg[i]
        -- parse comma separated plugin names
        for name in string.gmatch(plugins, '([^,]+)') do
            table.insert(pluginsnames, name)
        end
    end
end

jobs.init()
caas.create(os.getenv("CAAS_SERVER_PORT"), os.getenv("CAAS_SERVER_ADDR"))
    .handle("GET", "/dir/?(.*)", handledir)                   -- returns directory listings or file content
    .handle("POST", "/job/(.*)", handlepostjob)               -- registers new or starts existing job
    .handle("HEAD", "/job/?(.*)", handleheadjob)              -- returns presence of requested job
    .handle("DELETE", "/job/(.*)/(.*)", handledeleteinstance) -- stops job instance if running
    .handle("DELETE", "/job/(.*)", handledeletejob)           -- destroys a job
    .handle("GET", "/job/(.-)/(.*)", handlegetinstance)       -- returns the log of a job instance
    .handle("GET", "/job/?(.*)", handlegetjob)                -- returns all jobs and info about their instance statuses

-- load plugins
for _, name in ipairs(pluginsnames) do
    local plugin = require('caas.plugin.'..name)
    print(string.format('Loading plugin %s %s', plugin._NAME, plugin._VERSION))
    plugin.init(caas)
end

-- starts caas server
caas.start()
