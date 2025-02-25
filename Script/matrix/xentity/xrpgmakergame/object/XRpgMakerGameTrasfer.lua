local XRpgMakerGameObject = require("XEntity/XRpgMakerGame/Object/XRpgMakerGameObject")

local type = type
local pairs = pairs
local Vector3 = CS.UnityEngine.Vector3

--传送对象
local XRpgMakerGameTrasfer = XClass(XRpgMakerGameObject, "XRpgMakerGameTrasfer")

--播放传送失败特效
function XRpgMakerGameTrasfer:PlayTransFailEffect()
    local color = XRpgMakerGameConfigs.GetTransferPointColor(self:GetId())
    local key = XRpgMakerGameConfigs.GetTransferPointColorKey(color)
    local modelPath = XRpgMakerGameConfigs.GetRpgMakerGameModelPath(key)
    self:LoadModel(modelPath, nil, nil, key)
    XSoundManager.PlaySoundByType(XSoundManager.UiBasicsMusic.RpgMakerGame_TransferFail, XSoundManager.SoundType.Sound)
end

function XRpgMakerGameTrasfer:OnLoadComplete()
    self:SetActive(false)
    self:SetActive(true)
    XRpgMakerGameTrasfer.Super.OnLoadComplete(self)
end

return XRpgMakerGameTrasfer