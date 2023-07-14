XCode = {}

local XCodeKeyMap = nil

local mt = {
    __index  = function(t, k)
        local code = XCodeKeyMap[k]
        if code then
            t[k] = code
            XCodeKeyMap[k] = nil
        else
            XLog.Error("XCode Key:" .. tostring(k) .. "������, �����XCodeText.tab����������ȷ�ϸ�Key�Ƿ����ã�XCode.cs�ж��壩")
        end
        return code
    end
} 
setmetatable(XCode, mt)

function XCode.Init()
    if XCodeKeyMap then
        return
    end
    XCodeKeyMap = {}

    local TABLE_CODE_TEXT = "Share/Text/CodeText.tab"
    local codeTextTemplates = XTableManager.ReadByStringKey(TABLE_CODE_TEXT, XTable.XTableCodeText, "Key")
    for k, v in pairs(codeTextTemplates) do
        XCodeKeyMap[k] = v.Id
    end
end
