-- 
local uv  = require "luv"
local EOL = "\r\n"
local _M = {
    _SERVER_SOFTWARE = "luvhttpd",
    _VERSION = "0.1",
    _MAX_CONNECTIONS = 128,
    handlers = {},
    log = print
}

function _M.create(port, host)
    port = port or 8080
    host = host or "0.0.0.0"

    local server = uv.new_tcp()
    server:bind(host, port)
    _M.log(string.format("%s is listening on %s:%s", _M._SERVER_SOFTWARE, host, port))
    server:listen(_M._MAX_CONNECTIONS, function(err)
        -- Make sure there was no problem setting up listen
        assert(not err, err)

        -- Accept the client
        local client = uv.new_tcp()
        server:accept(client)
        _M.onconnection(client)
    end)
    return _M
end

function _M.parsecommandline(req)
    assert(type(req.cmdline) == "string")
    local cmdparts = {}
    string.gsub(req.cmdline, "(%S*)(%S*)(%S*)", function (p) table.insert(cmdparts, p) end)
    req.method, req.uri, req.version = table.unpack(cmdparts)
    req.method = string.upper (req.method or 'GET')
    local parsed = _M.parseuri(req.uri or '/')
    req.path = parsed.path
    req.query = parsed.query
end

function _M.addheaderline(req, line)
    req.headers = req.headers or {}
    local _, _, name, value = string.find (line or "", "^([^: ]+)%s*:%s*(.+)")
    if not name then
        return nil
    end
    name = string.lower(name)
    if req.headers[name] then
        req.headers[name] = req.headers[name] .. "," .. value
    else
        req.headers[name] = value
    end
end

function _M.onconnection(client)
    local req = _M.makerequest(client)
    local res = _M.makeresponse(req)
    local handler
    local remaining
    local bodysent = 0
    local bodytotal = 0

    client:read_start(function (err, chunk)
        -- crash on errors
        assert(not err, err)

        if not chunk then
            if res.onclose then
                res.onclose()
            end
            res.close()
            return 
        end

        if not req.isreceivedheaders then
            -- consume request
            if remaining then
                chunk = remaining..chunk
            end
            local line
            line = chunk:match("(.-)\r\n")
            while line do
                if line == "" then
                    req.isreceivedheaders = true
                    chunk = chunk:sub(3)
                    bodytotal = tonumber(req.headers["content-length"]) or 0
                    break
                end
                if not req.cmdline then
                    req.cmdline = line
                    _M.parsecommandline(req)
                else
                    _M.addheaderline(req, line)
                end
                chunk = chunk:sub(line:len() + 3)
                line = chunk:match("(.-)\r\n")
            end
            remaining = chunk
        end

        if req.isreceivedheaders then
            -- match handler
            if not handler then
                handler = _M.matchhandler(req) or _M.err_404
                -- call handler once
                xpcall(function () 
                    handler(req, res)
                end, function (err)
                    _M.err_500(req, res, debug.traceback(err))
                end)
            end

            -- send request body to handler if wanted
            if req.ondata then
                chunk = remaining or chunk
                remaining = nil
                if chunk:len() < bodytotal - bodysent then
                    -- send partial body
                    req.ondata(chunk)
                    bodysent = bodysent + chunk:len()
                else
                    -- send remaining body
                    req.ondata(chunk:sub(1, bodytotal - bodysent))
                    bodysent = bodytotal
                end
                if bodysent == bodytotal then
                    -- request body sent
                    req.ondata(nil)
                end
            end
        end
    end)
end

function _M.sendresheaders(res)
    assert (not res.issentheaders, "Response headers are already sent")
    local client = res.req.client
    res.statusline = res.statusline or "HTTP/1.1 200 OK"
    client:write(res.statusline..EOL)
    local lowerheaders = {}
    for name, value in pairs (res.headers) do
        lowerheaders[string.lower(name)] = value
    end
    for name, value in pairs (lowerheaders) do
        client:write(string.format ("%s: %s"..EOL, name, value))
    end
    client:write(EOL)
    res.issentheaders = true
    _M.log(res.req.method, res.req.path, res.statusline)
end

function _M.handle(method, pattern, handler)
    table.insert(_M.handlers, { method, pattern, handler })
    return _M
end

function _M.matchhandler(req)
    for _, method_pattern in ipairs(_M.handlers) do
        local captures = { req.path:match(method_pattern[2]) }
        if method_pattern[1] == req.method and #captures > 0 then
            req.params = captures
            return method_pattern[3]
        end
    end
end

function _M.makerequest(client)
    local req = {
        client = client
    }
    return req
end

function _M.makeresponse(req)
    local res
    res = {
        req = req,
        headers = {
            Date = os.date ("!%a, %d %b %Y %H:%M:%S GMT"),
            Server = string.format("%s %s", _M._SERVER_SOFTWARE, _M._VERSION)
        },
        -- sends data to client
        write = function(data)
            -- send headers if not yet
            if not res.issentheaders then
                _M.sendresheaders(res)
            end
            -- send data
            if data then
                req.client:write(tostring(data))
            else
                -- empty data is response end indicator
                if not res.closed then
                    req.client:shutdown()
                    req.client:close()
                    res.closed = true
                end
            end
        end,
        -- send data if any and close client
        close = function(data)
            res.write(data)
            if data then
                res.write()
            end
        end
    }
    return res
end

-- http error template 
function _M.makereserr(res, errcode, errname, errdesc)
    local errmsg = string.format ([[
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<HTML><HEAD>
<TITLE>%d %s</TITLE>
</HEAD><BODY>
<H1>%s</H1>
%s<P>
</BODY></HTML>
]], errcode, errname, errname, errdesc)
    res.statusline = string.format("HTTP/1.1 %d %s", errcode, errname)
    res.headers["content-type"] = "text/html"
    res.headers["content-length"] = errmsg:len()
    res.close(errmsg)
end

-- 404 response handler
function _M.err_404(req, res)
    _M.makereserr(res, 404, "Not Found", string.format("The requested path %s was not found on this server", req.path))
end

-- 500 response handler
function _M.err_500(req, res, err)
    _M.makereserr(res, 500, "Internal Server Error", string.format("<pre>%s</pre>", err))
end

-- basic uri parser
function _M.parseuri(uri)
    assert(type(uri) == "string")
    assert(uri ~= "")
    local parsed = {}

    -- remove whitespace
    uri = string.gsub(uri, "%s", "")

    -- get query string
    uri = string.gsub(uri, "%?(.*)", function(q)
        parsed.query = q
        return ""
    end)
    -- get path
    if uri ~= "" then parsed.path = uri end
    return parsed
end

_M.start = uv.run

return _M
