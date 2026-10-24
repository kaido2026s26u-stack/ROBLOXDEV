-- RXDEV render meter. Five Stats samples/second, two UI updates/second.
local module = {}
function module.start(ui, graphics, connect)
    local RunService = game:GetService("RunService")
    local performance, fill = ui.performance, ui.fill
    local sampleCount, sampleSeconds = 0, 0
    local meterStage, readyAt, nextMeterUI, nextStatsRead = nil, 0, 0, 0
    local stats
    pcall(function() stats = game:GetService("Stats") end)
    local properties = {"RenderCPUFrameTime", "RenderGPUFrameTime", "SceneDrawcallCount", "SceneTriangleCount"}
    local sums, counts, reported = {}, {}, {}
    local function clearSamples()
        sampleCount, sampleSeconds = 0, 0
        table.clear(sums);table.clear(counts)
    end
    local function readStats()
        for index, property in ipairs(properties) do
            local ok, value = pcall(function() return stats[property] end)
            local valid = ok and type(value)=="number" and value==value and value<math.huge
                and (index<=2 and value>0 or index>2 and value>=0)
            if valid then
                sums[index]=(sums[index] or 0)+value
                counts[index]=(counts[index] or 0)+1
            end
            if not reported[index] then
                reported[index]=true
                warn(string.format("[RXDEV Meter] Metric %s: %s",property,
                    valid and tostring(value) or "N/A (not available/invalid)"))
            end
        end
    end
    local function average(index)
        return counts[index] and sums[index]/counts[index] or nil
    end
    local function msText(value)
        return value and string.format("%.2f",value*1000) or "N/A"
    end
    connect(RunService.RenderStepped, function(dt)
        local now = os.clock()
        local stage = graphics.stage()
        local applying = graphics.busy()
        if stage ~= meterStage or applying then
            meterStage = stage
            clearSamples()
            readyAt = now + 1
        end
        if now >= readyAt then
            if dt > 0 and dt < math.huge then sampleCount+=1;sampleSeconds+=dt end
            -- Four scalar reads at most five times per second, not per rendered frame.
            if now >= nextStatsRead then nextStatsRead=now+0.2;readStats() end
        end
        if now < nextMeterUI then return end
        nextMeterUI=now+0.5
        local text
        if applying or now < readyAt then
            text="FPS -- | Render (ms)\nCPU -- | GPU -- (settling)\nDraw -- | Tri --"
            fill.Size=UDim2.fromScale(0,1)
            fill.BackgroundColor3=Color3.fromRGB(110,115,125)
        elseif sampleSeconds>=0.5 and sampleCount>0 then
            local fps=sampleCount/sampleSeconds
            local cpu,gpu,draw,tri=average(1),average(2),average(3),average(4)
            text=string.format("FPS %.1f | Render (ms)\nCPU %s | GPU %s\nDraw %s | Tri %s",fps,msText(cpu),msText(gpu),
                draw and string.format("%.0f",draw) or "N/A",tri and string.format("%.1fk",tri/1000) or "N/A")
            -- CPU/GPU overlap: never add them or label this as device utilization.
            -- Scale is a fixed 60-FPS rendering budget; missing metrics stay neutral.
            if cpu and gpu then
                local renderMs=math.max(cpu,gpu)*1000
                fill.Size=UDim2.fromScale(math.clamp(renderMs/(1000/60),0,1),1)
                fill.BackgroundColor3=if renderMs<=8.33 then Color3.fromRGB(80,200,130)
                    elseif renderMs<=16.67 then Color3.fromRGB(240,185,70) else Color3.fromRGB(230,90,90)
            else
                fill.Size=UDim2.fromScale(0,1)
                fill.BackgroundColor3=Color3.fromRGB(110,115,125)
            end
            clearSamples()
        else return end
        if performance.Text~=text then performance.Text=text end
    end)
end
return module
