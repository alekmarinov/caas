-- plugin module definition
local _M = {
    _NAME = 'logger',
    _VERSION = '1.0.0'
}

function _M.init(caas)
    local function logreq(req)
        print(os.date("%Y-%m-%d %H:%M:%S"), req.remote_ip, req.cmdline)
        for name, value in pairs(req.headers) do
            print("  "..name, value)
        end
    end
    for _, method in ipairs{"GET", "POST", "DELETE", "PUT", "PATCH"} do
        caas.filter(method, "/(.*)", logreq)
    end
end

return _M
