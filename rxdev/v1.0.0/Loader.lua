-- One loader per RXDEV launch: cached exports, shared in-flight requests, retry on error.
local module = {}
function module.new(base)
    local cache, pending, contracts = {}, {}, {Manifest={}}
    local function validate(name, value)
        assert(type(value) == "table", name .. " must return a table")
        for _, method in ipairs(contracts[name]) do
            assert(type(value[method]) == "function", name .. "." .. method .. " is missing")
        end
        return value
    end
    local function get(name)
        assert(contracts[name], "Unregistered RXDEV module: " .. tostring(name))
        if cache[name] then return cache[name] end
        local flight = pending[name]
        if flight then
            assert(flight.owner ~= coroutine.running(), "Circular module dependency: " .. name)
            flight.event.Event:Wait()
            if flight.error then error(flight.error, 0) end
            return flight.value
        end
        flight = {event=Instance.new("BindableEvent"), owner=coroutine.running()}
        pending[name] = flight
        local ok, result = pcall(function()
            local source = game:HttpGet(base .. name .. ".lua")
            local chunk, why = loadstring(source, "RXDEV_" .. name)
            assert(chunk, why)
            return validate(name, chunk())
        end)
        if ok then cache[name]=result;flight.value=result
        else flight.error="RXDEV " .. name .. ": " .. tostring(result) end
        pending[name] = nil
        flight.event:Fire()
        flight.event:Destroy()
        if not ok then error(flight.error, 0) end
        return result
    end
    return {get=get, configure=function(spec)
        for name, methods in pairs(spec) do
            assert(name:match("^[%w_]+$") and type(methods)=="table", "Invalid module contract")
            contracts[name]=methods
        end
    end}
end
return module
