-- Executor workspace storage. Only RXDEV/AutoChat is used; no flat-file fallback.
local module={}
local BASE="RXDEV/AutoChat"
local REPORTS=BASE.."/reports"
function module.new()
    local sequence=0
    local controller={}
    local function prepare()
        for _,entry in ipairs({{"isfolder",isfolder},{"makefolder",makefolder},{"isfile",isfile},{"writefile",writefile},{"readfile",readfile}}) do
            assert(type(entry[2])=="function",entry[1].." unavailable")
        end
        for _,dir in ipairs({"RXDEV",BASE,REPORTS}) do
            assert(not isfile(dir),"A file occupies folder path: "..dir)
            if not isfolder(dir) then makefolder(dir) end
            assert(isfolder(dir),"Folder creation not confirmed: "..dir)
        end
    end
    local function writeVerified(path,content)
        writefile(path,content)
        assert(readfile(path)==content,"Read-back mismatch: "..path)
    end
    function controller.test()
        local ok,why=pcall(function()
            prepare()
            writeVerified(BASE.."/workspace_check.txt","RXDEV AutoChat workspace check\nフォルダ作成・日本語の読み書き確認\n")
        end)
        return ok,ok and (BASE.."/workspace_check.txt") or tostring(why)
    end
    function controller.save(text,data)
        local paths={}
        local ok,why=pcall(function()
            prepare()
            local encoded=game:GetService("HttpService"):JSONEncode(data)
            local stem
            for _=1,1000 do
                sequence+=1
                local candidate=REPORTS.."/autochat_"..os.time().."_"..string.format("%03d",sequence)
                if not isfile(candidate..".txt") and not isfile(candidate..".json") then stem=candidate;break end
            end
            assert(stem,"Could not allocate a fresh report filename")
            writeVerified(stem..".txt",text);table.insert(paths,stem..".txt")
            writeVerified(stem..".json",encoded);table.insert(paths,stem..".json")
        end)
        return ok,{paths=paths,error=not ok and tostring(why) or nil,directory=REPORTS}
    end
    return controller
end
return module
