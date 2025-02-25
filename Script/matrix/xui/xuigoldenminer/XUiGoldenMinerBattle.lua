local XGoldenMinerBaseObj = require("XEntity/XGoldenMiner/Object/XGoldenMinerBaseObj")
local XGoldenMinerBoom = require("XEntity/XGoldenMiner/Object/XGoldenMinerBoom")
local XGoldenMinerMouse = require("XEntity/XGoldenMiner/Object/XGoldenMinerMouse")
local XGoldenMinerRedEnvelope = require("XEntity/XGoldenMiner/Object/XGoldenMinerRedEnvelope")
local XGoldenMinerItemChangeInfo = require("XEntity/XGoldenMiner/Settle/XGoldenMinerItemChangeInfo")
local XGoldenMinerSettlementInfo = require("XEntity/XGoldenMiner/Settle/XGoldenMinerSettlementInfo")
local XUiItemPanel = require("XUi/XUiGoldenMiner/Panel/XUiItemPanel")
local XUiBuffPanel = require("XUi/XUiGoldenMiner/Panel/XUiBuffPanel")

--绳子状态
local RopeState = {
    Rock = 1, --常态摇摆
    Stretch = 2, --拉伸
    Shorten = 3, --回收
    Stop = 4,   --停止动作
}

--矿工状态
local HumenState = {
    Idle = 1, --常态
    MoveLeft = 2, --向左移动中
    MoveRight = 3, --向右移动中
}

--玩法倒计时颜色
local TxtTimeColor = {
    [true] = CS.UnityEngine.Color.white, 
    [false] = CS.UnityEngine.Color.red
}


local MILLISECOND = 1000    --毫秒
local PERCENT = XGoldenMinerConfigs.Percent         --倍率
local ROLE_MOVE_RANGE_PERCENT = XGoldenMinerConfigs.GetRoleMoveRangePercent()   --角色移动范围百分比
local GAME_NEAR_END_TIME = XGoldenMinerConfigs.GetGameNearEndTime() --临近结束的时间（单位：秒）
local GAME_STOP_COUNTDOWN = XGoldenMinerConfigs.GetGameStopCountdown()  --暂停倒计时（单位：秒）
local SHORTEN_SPEED_PARAMETER = XGoldenMinerConfigs.GetShortenSpeedParameter()
local SHORTEN_MIN_SPEED = XGoldenMinerConfigs.GetShortenMinSpeed()
local ROLE_GRAP_SUCCESS_TIME = XGoldenMinerConfigs.GetRoleGrapSuccessTime() --抓到物品切换回默认表情的时间（毫秒）
local USE_ITEM_SPEED = XGoldenMinerConfigs.GetUseItemSpeed()    --使用道具到抓取物的速度
local USE_BOOM_EFFECT = XGoldenMinerConfigs.GetUseBoomEffect()  --使用炸弹特效
local FINAL_SHIP_MAX_COUNT = XGoldenMinerConfigs.GetFinalShipMaxCount() --显示完全体的飞船需要升满的升级项

local CSUnityEngineTime = CS.UnityEngine.Time
local CSXResourceManagerLoad = CS.XResourceManager.Load
local CSUiButtonStateNormal = CS.UiButtonState.Normal
local CSUiButtonStateSelect = CS.UiButtonState.Select
local MathFloor = math.floor
local MahtAbs = math.abs
local TableInsert = table.insert

--黄金矿工玩法界面
local XUiGoldenMinerBattle = XLuaUiManager.Register(XLuaUi, "UiGoldenMinerBattle")

function XUiGoldenMinerBattle:OnAwake()
    self:InitObj()

    self.CurFaceId = nil    --当前使用的表情Id
    self.SettlementInfo = XGoldenMinerSettlementInfo.New()
    self.DataDb = XDataCenter.GoldenMinerManager.GetGoldenMinerDataDb()
    self.HumenPosY = self.Humen.transform.localPosition.y   --矿工Y轴位置
    self.RopeRockDir = Vector3.back --绳子摇摆的方向
    self.PreFaceUrlPath = nil   --上一个表情的路径
    self.CurNearEndTime = 0 --当前临近结束时间
    self.IsCloseBattle = false  --游戏结束等后端传来数据再关闭界面
    self.IsFinishSuccess = true    --通关请求服务器是否返回成功
    self:SetIsPlayRopeOpenAnima(true)

    self:SetNotActiveBoomTimes(0)
    self:SetCurShortenSpeed(0)  --抓到东西时回收的速度
    self.ResourcePool = {}
    self.EffectPool = {}
    self.CurTriggerObjDic = {}	--钩子抓到的对象字典
    self.CurTriggerObjSettleList = {} --钩子抓到并结算成得分的对象列表

    self:RegisterButtonEvent()
    self.ItemPanel = XUiItemPanel.New(self.PanelSkillParent, handler(self, self.UseItem))
    self.BuffPanel = XUiBuffPanel.New(self.PanelBuffParent, self)

    self:HideCurScoreChange()
end

function XUiGoldenMinerBattle:OnStart()
    local dataDb = self.DataDb
    local characterId = XDataCenter.GoldenMinerManager.GetUseCharacterId()
    self.CurStageId, self.CurStageIndex = dataDb:GetCurStageId()
    self.MapId = dataDb:GetStageMapId(self.CurStageId)
    self.LastTime = XGoldenMinerConfigs.GetMapTime(self.MapId)
    self.BeforeScore = dataDb:GetStageScores()
    self.CurMapScore = self.BeforeScore --在当前地图中的得分
    self.SettlementItems = dataDb:GetItemColumns()
    self.DefaultFaceImgPath = XGoldenMinerConfigs.GetCharacterDefaultFace(characterId)  --角色默认表情资源路径
    self.IsPlayNearEndAnima = true  --是否播放临近结束时的动画

    --飞碟特效首次打开界面隐藏，等倒计时结束后再显示
    self:SetHumenEffectActive(false)
    --背景的Canvas层级大于0会挡住特效，强制设为0
    if self.FullScreenBackground then
        self.FullScreenBackground.sortingOrder = 0
    end

    --目标得分
    self.TargetScoreData = dataDb:GetCurStageTargetScore()
    self.TargetScore.text = XUiHelper.GetText("GoldenMinerPlayTargetScore", self.TargetScoreData)

    self.TxtNumber.text = XUiHelper.GetText("GoldenMinerCurStage", self.CurStageIndex)

    --设置发射钩爪按钮音效的音量为原大小
    self.BtnChange.transform:GetComponent("XUguiPlaySound").VolumePercent = 100
end

function XUiGoldenMinerBattle:OnEnable()
    XUiGoldenMinerBattle.Super.OnEnable(self)
    XEventManager.AddEventListener(XEventId.EVENT_APPLICATION_PAUSE, self.ApplicationPause, self)
    self:Init()
end

function XUiGoldenMinerBattle:Init()
    --等异形屏适配宽度后再计算
    XScheduleManager.ScheduleOnce(function()
        if XTool.UObjIsNil(self.GameObject) then
            return
        end

        local areaPanel = XUiHelper.TryGetComponent(self.Ui.Transform, "SafeAreaContentPane")
        self.RectSize = areaPanel:GetComponent("RectTransform").rect.size
        self.RoleMoveRange = self.RectSize.x * ROLE_MOVE_RANGE_PERCENT

        self:UpdateCurScore()
        self:InitMap(self.MapId)
        self:SetHumenCurState(HumenState.Idle)
        self:SetTxtTime(self.LastTime)
        self:InitEdgeTriggerEnter()
        self:InitTimes()
        self:SetRoleDefaultFace()
        self:InitHumenAppearance()

        self.ItemPanel:UpdateItemColumns()
        self:UpdateBuff()
        self:InitRope()
        self:SetCurState(RopeState.Rock)
        self:StartGameStopCountdown()
    end, 10)
end

function XUiGoldenMinerBattle:OnDisable()
    XUiGoldenMinerBattle.Super.OnDisable(self)
    XEventManager.RemoveEventListener(XEventId.EVENT_APPLICATION_PAUSE, self.ApplicationPause, self)
    self:StopTimer()
    self:StopGameStopCountdown()
    self:StopCurScoreChangeAnima()
end

function XUiGoldenMinerBattle:OnDestroy()
    for _, resource in pairs(self.ResourcePool) do
        resource:Release()
    end
    if not XTool.UObjIsNil(self.GoInputHandler) then
        self.GoInputHandler:RemoveAllListeners()
    end
    self.GoInputHandler = nil
    self:StopRopeSoundPlay()
end

function XUiGoldenMinerBattle:InitObj()
    self.FullScreenBackground = XUiHelper.TryGetComponent(self.Transform, "FullScreenBackground", "Canvas")
end

--初始化飞船外观
function XUiGoldenMinerBattle:InitHumenAppearance()
    local humenImageObj = XUiHelper.TryGetComponent(self.Humen.transform, "Humen", "RawImage")
    if not humenImageObj then
        return
    end

    local dataDb = self.DataDb
    local upgradeList = dataDb:GetAllUpgradeStrengthenList()
    local totalNum = 0
    local shipKey = XGoldenMinerConfigs.ShipAppearanceKey.DefaultShip

    --设置飞船外观
    for _, strengthenDb in ipairs(upgradeList) do
        if not string.IsNilOrEmpty(strengthenDb:GetLvMaxShipKey()) and strengthenDb:IsMaxLv() then
            totalNum = totalNum + 1
            shipKey = strengthenDb:GetLvMaxShipKey()
        end
    end
    if totalNum >= FINAL_SHIP_MAX_COUNT then
        shipKey = XGoldenMinerConfigs.ShipAppearanceKey.FinalShip
    end
    humenImageObj:SetRawImage(XGoldenMinerConfigs.GetShipImagePath(shipKey))

    --设置飞船大小
    local shipSizeWidth, shipSizeHeight
    if shipKey == XGoldenMinerConfigs.ShipAppearanceKey.MaxSpeedShip then
        shipSizeWidth, shipSizeHeight = XGoldenMinerConfigs.GetShipSize(XGoldenMinerConfigs.ShipAppearanceSizeKey.MaxSpeedShipSize)
    elseif shipKey == XGoldenMinerConfigs.ShipAppearanceKey.MaxClampShip then
        shipSizeWidth, shipSizeHeight = XGoldenMinerConfigs.GetShipSize(XGoldenMinerConfigs.ShipAppearanceSizeKey.MaxClampShipSize)
    elseif shipKey == XGoldenMinerConfigs.ShipAppearanceKey.FinalShip then
        shipSizeWidth, shipSizeHeight = XGoldenMinerConfigs.GetShipSize(XGoldenMinerConfigs.ShipAppearanceSizeKey.FinalShipSize)
    else
        shipSizeWidth, shipSizeHeight = XGoldenMinerConfigs.GetShipSize(XGoldenMinerConfigs.ShipAppearanceSizeKey.DefaultShipSize)
    end
    humenImageObj.transform:GetComponent("RectTransform").rect.size = Vector2(shipSizeWidth, shipSizeHeight)
end

--初始化当前使用类型的钩爪
function XUiGoldenMinerBattle:InitRope()
    local falculaType = self:GetFalculaType()
    self.NormalRope.gameObject:SetActiveEx(falculaType == XGoldenMinerConfigs.FalculaType.Normal)
    self.MagneticRope.gameObject:SetActiveEx(falculaType == XGoldenMinerConfigs.FalculaType.Magnetic)
    self.BigRope.gameObject:SetActiveEx(falculaType == XGoldenMinerConfigs.FalculaType.Big)

    self.Rope = (falculaType == XGoldenMinerConfigs.FalculaType.Magnetic and self.MagneticRope) or
        (falculaType == XGoldenMinerConfigs.FalculaType.Big and self.BigRope) or
        self.NormalRope
    --普通和电磁钩爪的触发器
    self.RopeCordCollider = (falculaType == XGoldenMinerConfigs.FalculaType.Magnetic and self.MagneticRopeCordCollider) or self.NormalCordCollider
    --绳子Trans
    self.RopeTrans = self.Rope.transform
    self.RopeRectTrans = self.Rope.gameObject:GetComponent("RectTransform")
    --绳子最短长度
    self.RopeMinLength = self.RopeRectTrans.sizeDelta.y
    --绳子最长长度
    self.RopeMaxLength = math.ceil(math.sqrt(self.RectSize.x ^ 2 + self.RectSize.y ^ 2))
    --钩爪
    local ropeCord = XUiHelper.TryGetComponent(self.RopeTrans, "RopeCord")
    self.RopeCordTrans = ropeCord.transform
    self.RopeCordOriginPosY = self.RopeCordTrans.localPosition.y
    --左钩子
    local ropeCordLeft = XUiHelper.TryGetComponent(self.RopeTrans, "RopeCordLeft")
    self.RopeCordLeftTrans = ropeCordLeft and ropeCordLeft.transform
    self.RopeCordLeftOriginPosY = self.RopeCordLeftTrans and self.RopeCordLeftTrans.localPosition.y
    --右钩子
    local ropeCordRight = XUiHelper.TryGetComponent(self.RopeTrans, "RopeCordRight")
    self.RopeCordRightTrans = ropeCordRight and ropeCordRight.transform
    self.RopeCordRightOriginPosY = self.RopeCordRightTrans and self.RopeCordRightTrans.localPosition.y
    --电磁类型的钩子
    local ropeCordMagnetic = XUiHelper.TryGetComponent(self.RopeTrans, "RopeCordMagnetic")
    self.RopeCordMagneticTrans = ropeCordMagnetic and ropeCordMagnetic.transform
    self.RopeCordMagneticOriginPosY = self.RopeCordMagneticTrans and self.RopeCordMagneticTrans.localPosition.y
    --钩环
    local shackle = XUiHelper.TryGetComponent(self.RopeTrans, "Shackle")
    self.ShackleTrans = shackle and shackle.transform
    self.ShackleOriginPosY = self.ShackleTrans and self.ShackleTrans.localPosition.y
    --抓取到的对象的父节点
    self.TriggerObjs = XUiHelper.TryGetComponent(self.RopeCordTrans, "TriggerObjs")

    self:InitAim()
    self:SetRopeLength(self.RopeMinLength)
end

--初始化瞄准线
function XUiGoldenMinerBattle:InitAim()
    self.Aim = XUiHelper.TryGetComponent(self.RopeCordTrans, "Aim")
    local length = math.ceil(math.sqrt(self.RectSize.x ^ 2 + self.RectSize.y ^ 2))
    local sizeDelta = self.Aim.gameObject:GetComponent("RectTransform").sizeDelta
    self.Aim.gameObject:GetComponent("RectTransform").sizeDelta = Vector2(sizeDelta.x, length)
end

function XUiGoldenMinerBattle:InitTimes()
    self:SetAutoCloseInfo(XDataCenter.GoldenMinerManager.GetActivityEndTime(), function(isClose)
        if isClose then
            XDataCenter.GoldenMinerManager.HandleActivityEndTime()
            return
        end
    end, nil, 0)
end

--初始化地图边界触发器
function XUiGoldenMinerBattle:InitEdgeTriggerEnter()
    self.EdgeLeft:AddTriggerEnter2DCallback(function(collider) self:OnEdgeTriggerEnter(collider) end)
    self.EdgeRight:AddTriggerEnter2DCallback(function(collider) self:OnEdgeTriggerEnter(collider) end)
    self.EdgeTop:AddTriggerEnter2DCallback(function(collider) self:OnEdgeTriggerEnter(collider) end)
    self.EdgeBottom:AddTriggerEnter2DCallback(function(collider) self:OnEdgeTriggerEnter(collider) end)

    local rectSizeX, rectSizeY = self.RectSize.x, self.RectSize.y
    self.EdgeLeftBox.size = Vector2(self.EdgeLeftBox.size.x, rectSizeY)
    self.EdgeRightBox.size = Vector2(self.EdgeRightBox.size.x, rectSizeY)
    self.EdgeTopBox.size = Vector2(rectSizeX, self.EdgeTopBox.size.y)
    self.EdgeBottomBox.size = Vector2(rectSizeX, self.EdgeBottomBox.size.y)
end

--初始化地图中的抓取物
function XUiGoldenMinerBattle:InitMap(mapId)
    self.MouseObjList = {}
    self.BoomObjList = {}
    local stoneIdList = XGoldenMinerConfigs.GetMapStoneId(mapId)
    local grapObj
    local triggerCb = handler(self, self.TrigerCallback)
    local resourceManagerLoadFunc = handler(self, self.ResourceManagerLoad)

    for i, stoneId in ipairs(stoneIdList) do
        local resource = self:ResourceManagerLoad(XGoldenMinerConfigs.GetStonePrefab(stoneId))
        local obj = XUiHelper.Instantiate(resource.Asset)
        local stoneType = XGoldenMinerConfigs.GetStoneType(stoneId)
        if stoneType == XGoldenMinerConfigs.StoneType.Boom then
            grapObj = XGoldenMinerBoom.New(obj, stoneId, i, triggerCb, resourceManagerLoadFunc)
            grapObj:InitTriggerBoomFunc(handler(self, self.TriggerBoom))
            TableInsert(self.BoomObjList, grapObj)
        elseif stoneType == XGoldenMinerConfigs.StoneType.Mouse then
            grapObj = XGoldenMinerMouse.New(obj, stoneId, i, triggerCb, resourceManagerLoadFunc)
            TableInsert(self.MouseObjList, grapObj)
        elseif stoneType == XGoldenMinerConfigs.StoneType.RedEnvelope then
            grapObj = XGoldenMinerRedEnvelope.New(obj, stoneId, i, triggerCb, resourceManagerLoadFunc)
        else
            grapObj = XGoldenMinerBaseObj.New(obj, stoneId, i, triggerCb, resourceManagerLoadFunc)
        end

        obj.transform:SetParent(self.PanelStone, false)
        grapObj:Init(self.MapId, self.RectSize, self.PanelStone)
    end
end

-----------------使用道具 begin--------------------
function XUiGoldenMinerBattle:UseItem(itemGrid)
    local itemColumn = itemGrid:GetItemColumn()
    local itemGridIndex = itemColumn:GetGridIndex()
    if not XDataCenter.GoldenMinerManager.IsUseItem(itemGridIndex) then
        return
    end

    local itemId = itemColumn:GetItemId()
    local buffId = XGoldenMinerConfigs.GetItemBuffId(itemId)
    local buffType = XGoldenMinerConfigs.GetBuffType(buffId)
    local params = XGoldenMinerConfigs.GetBuffParams(buffId)

    if buffType == XGoldenMinerConfigs.BuffType.GoldenMinerBoom then
        --绳子回收且有抓取物时，使用炸弹消灭抓取物
        if self:GetCurState() ~= RopeState.Shorten or XTool.IsTableEmpty(self.CurTriggerObjDic) then
            return
        end
        self:UseBoom()
    elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerStoneChangeGold then
        --正在拉回的物品变为同样重量的金块
        if self:GetCurState() ~= RopeState.Shorten or XTool.IsTableEmpty(self.CurTriggerObjDic) then
            return
        end
        for k, goldenMinerObject in pairs(self.CurTriggerObjDic) do
            goldenMinerObject:ChangeToGold()
        end
        self:SetRoleFaceByGroup(XGoldenMinerConfigs.FaceGroup.RoleUseStoneChangeGold, self:GetCurTriggerObjTotalScore())
    elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerMouseStop then
        --所有的鼬鼠停止移动一段时间
        for _, mouseObj in ipairs(self.MouseObjList) do
            mouseObj:StopMoveTime(tonumber(params[1]))
        end
        --鼬鼠恢复移动的时间
        self.MouseRecoverMoveTime = self.LastTime - tonumber(params[1])
    elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerNotActiveBoom then
        --不激活炸弹箱
        local curNotActiveBoomTimes = self:GetNotActiveBoomTimes()
        self:SetNotActiveBoomTimes(curNotActiveBoomTimes + tonumber(params[1]))
        self:SetIsActiveBoom(false)
        self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleUseNotActiveBoom)
    elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerShortenSpeed then
        --拉回速度变为N倍
        if self:GetCurState() == RopeState.Shorten then
            self:UpdateCurShortenSpeed(self.ShortenSpeed * tonumber(params[1]) / PERCENT)
        end
        self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleUseShortenSpeed)
    else
        return
    end

    self:PlayUseItemSound(itemId)
    itemGrid:SetRImgIconActive(false)
    self.DataDb:UseItem(itemGridIndex)
    self:UpdateItemChangeInfo(itemGridIndex, XGoldenMinerConfigs.ItemChangeType.OnUse)
end

--播放使用道具音效
function XUiGoldenMinerBattle:PlayUseItemSound(itemId)
    local soundId = XGoldenMinerConfigs.GetItemUseSoundId(itemId)
    if not XTool.IsNumberValid(soundId) then
        return
    end

    XSoundManager.PlaySoundByType(soundId, XSoundManager.SoundType.Sound)
end

--使用炸弹
function XUiGoldenMinerBattle:UseBoom()
    self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleUseBoom)

    local triggerObjsPos = self.PanelPlay.transform:InverseTransformPoint(self.TriggerObjs.transform.position)
    self:LoadEffect(USE_BOOM_EFFECT, self.PanelPlay, triggerObjsPos)

    local score = self:GetCurTriggerObjTotalScore()
    local boomAfterScore = XGoldenMinerConfigs.GetFaceScore(XGoldenMinerConfigs.FaceId.RoleUseBoomAfter)
    self:SetRoleFace(score >= boomAfterScore and XGoldenMinerConfigs.FaceId.RoleUseBoomAfter or XGoldenMinerConfigs.FaceId.RoleUseBoom)

    self:RemoveCurTriggerObjDic(true)
end

function XUiGoldenMinerBattle:UpdateItemChangeInfo(itemGridIndex, status)
    local itemChangeInfo = XGoldenMinerItemChangeInfo.New()
    local itemDb = self.DataDb:GetItemColumnByIndex(itemGridIndex)
    itemChangeInfo:UpdateData({
        ItemId = itemDb:GetClientItemId(),
        Status = status,
        GridIndex = itemGridIndex
    })
    self.SettlementInfo:InsertSettlementItem(itemChangeInfo)
end
-----------------使用道具 end--------------------

function XUiGoldenMinerBattle:StartTimer()
    self:StopTimer()
    self.Timer = XScheduleManager.ScheduleForeverEx(handler(self, self.Update), 0)
    self:CheckRopeSoundPlay()
end

function XUiGoldenMinerBattle:StopTimer()
    if self.Timer then
        XScheduleManager.UnSchedule(self.Timer)
        self.Timer = nil
    end
    self:StopRopeSoundPlay()
end

function XUiGoldenMinerBattle:RegisterButtonEvent()
    self:RegisterClickEvent(self.BtnStop, self.OnBtnStopClick)
    self:RegisterClickEvent(self.BtnChange, self.OnBtnChangeClick)
    self.GoInputHandler:AddPointerDownListener(function(eventData) self:OnPointerDown(eventData) end)
    self.GoInputHandler:AddPointerUpListener(function(eventData) self:OnPointerUp(eventData) end)
end

--抛出绳子
function XUiGoldenMinerBattle:OnBtnChangeClick()
    if self:GetCurState() ~= RopeState.Rock then
        return
    end


    self:OnPointerUp()
    self:SetCurState(RopeState.Stretch)
    self.SettlementInfo:AddLaunchingClawCount()
    XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetStretchSound(), XSoundManager.SoundType.Sound)
end

---------------暂停相关 begin--------------------
function XUiGoldenMinerBattle:OnBtnStopClick()
    self.BtnStop:SetButtonState(CSUiButtonStateSelect)
    self:StopTimer()
    local title = XUiHelper.GetText("GoldenMinerStopTipsTitle")
    local closeCallback = function()
        self.BtnStop:SetButtonState(CSUiButtonStateNormal)
        self:StartGameStopCountdown()
    end
    local sureCallback = handler(self, self.QuickDialog)
    local extraData = {
        sureText = XUiHelper.GetText("GoldenMinerStopTipsCloseText"),
        closeText = XUiHelper.GetText("GoldenMinerStopTipsSureText")
    }
    XLuaUiManager.Open("UiGoldenMinerDialog", title, "", closeCallback, sureCallback, extraData)
end

--二次确认退出弹窗
function XUiGoldenMinerBattle:QuickDialog()
    local title = XUiHelper.GetText("GoldenMinerQuickTipsTitle")
    local desc = XUiHelper.GetText("GoldenMinerQuickTipsDesc")
    local closeCallback = handler(self, self.OnBtnStopClick)
    local sureCallback = function()
        self:UpdateSettlementInfo()
        XDataCenter.GoldenMinerManager.RequestGoldenMinerExitGame(self.CurStageId, function()
            XLuaUiManager.PopThenOpen("UiGoldenMinerMain")
        end, self.SettlementInfo, self.CurMapScore, self.BeforeScore)
    end
    XLuaUiManager.Open("UiGoldenMinerDialog", title, desc, closeCallback, sureCallback)
end

--解除暂停倒计时
function XUiGoldenMinerBattle:StartGameStopCountdown()
    self:StopGameStopCountdown()
    local time = GAME_STOP_COUNTDOWN
    self.GameStopTimer = XScheduleManager.ScheduleForeverEx(function()
        if time <= 0 then
            self.PanelGuide.gameObject:SetActiveEx(false)
            self:SetHumenEffectActive(true)
            self:StopGameStopCountdown()
            self:StartTimer()
            return
        end

        self.TxtCountdown.text = string.format("%02d", time)
        self.PanelGuide.gameObject:SetActiveEx(true)
        time = time - 1
    end, XScheduleManager.SECOND)
end

function XUiGoldenMinerBattle:StopGameStopCountdown()
    if self.GameStopTimer then
        XScheduleManager.UnSchedule(self.GameStopTimer)
        self.GameStopTimer = nil
    end
end

--程序暂停
function XUiGoldenMinerBattle:ApplicationPause(isPause)
    if isPause then
        self:OnBtnStopClick()
    end
end
---------------暂停相关 end--------------------

local _IsNearEnd
local _IsPlayTimeEnable
function XUiGoldenMinerBattle:SetTxtTime(time)
    if not XTool.IsNumberValid(self.CurNearEndTime) then
        self.CurNearEndTime = time - 1
    end

    _IsPlayTimeEnable = time - self.CurNearEndTime < 0
    _IsNearEnd = time <= GAME_NEAR_END_TIME

    --临近结束时间后，每隔1秒播放一次动画
    if _IsNearEnd and _IsPlayTimeEnable then
        self.CurNearEndTime = time - 1
        self:PlayAnimation("TimeEnable")
    end

    self.TxtTime.text = XUiHelper.GetTime(time, XUiHelper.TimeFormatType.ESCAPE_REMAIN_TIME)
    self.TxtTime.color = TxtTimeColor[not _IsNearEnd]
end

--更新Buff
function XUiGoldenMinerBattle:UpdateBuff()
    self.BuffPanel:UpdateBuff()

    self:SetFalculaType(XGoldenMinerConfigs.FalculaType.Normal)
    self:SetStretchSpeed(XGoldenMinerConfigs.GetRopeStretchSpeed())     --绳子伸长基本速度
    self:SetShortenSpeed(XGoldenMinerConfigs.GetRopeShortenSpeed())     --绳子拉回基本速度
    self:SetHumenMoveSpeed(XGoldenMinerConfigs.GetHumenMoveSpeed())     --飞碟移动速度
    self:SetRopeRockSpeed(XGoldenMinerConfigs.GetRopeRockSpeed())       --绳子摇摆速度
    self.StoneUpScoreDic = {}   --抓取物获得的分数变为原本的X倍，默认为1

    local ownBuffDic = XDataCenter.GoldenMinerManager.GetOwnBuffDic()
    local stoneScoreBuffs = ownBuffDic[XGoldenMinerConfigs.BuffType.GoldenMinerStoneScore]
    if not XTool.IsTableEmpty(stoneScoreBuffs) then
        for goldenMinerStoneType, params in pairs(stoneScoreBuffs) do
            self.StoneUpScoreDic[goldenMinerStoneType] = params[2] --各个不同类型的抓取物对应的倍率
        end
    end

    for buffType, params in pairs(ownBuffDic) do
        if buffType == XGoldenMinerConfigs.BuffType.GoldenMinerShortenSpeed then
            self:SetShortenSpeed(self.ShortenSpeed * params[1] / PERCENT)
        elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerNotActiveBoom then
            local curNotActiveBoomTimes = self:GetNotActiveBoomTimes()
            self:SetNotActiveBoomTimes(curNotActiveBoomTimes + params[1])
        elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerHumenSpeed then
            self:SetHumenMoveSpeed(self.HumenMoveSpeed * params[1] / PERCENT)
        elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerStretchSpeed then
            self:SetStretchSpeed(self.StretchSpeed * params[1] / PERCENT)
        elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerCordMode then
            self:SetFalculaType(params[1])
        elseif buffType == XGoldenMinerConfigs.BuffType.GoldenMinerAim then
            self:SetIsShowAim(true)
        end
    end
end

local _DeltaTime
local _CurState
function XUiGoldenMinerBattle:Update()
    _DeltaTime = self:GetDeltaTime()
    self.LastTime = self.LastTime - _DeltaTime
    self:SetTxtTime(self.LastTime)
    if MathFloor(self.LastTime) <= 0 then
        self:GameOver()
        return
    end

    _CurState = self:GetCurState()
    if _CurState == RopeState.Rock then
        self:Rock()
        self:SetRoleDefaultFace()
    elseif _CurState == RopeState.Stretch then
        self:Stretch()
        self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleStretch)
    elseif _CurState == RopeState.Shorten then
        self:Shorten()
    end

    if self.HumenCurState == HumenState.MoveLeft then
        self:HumenMoveLeft()
    elseif self.HumenCurState == HumenState.MoveRight then
        self:HumenMoveRight()
    end

    for _, mouseObj in ipairs(self.MouseObjList) do
        mouseObj:Move(_DeltaTime)
    end
end

-----------Buff相关 begin---------------
--设置回收绳子基本速度
function XUiGoldenMinerBattle:SetShortenSpeed(speed)
    self.ShortenSpeed = speed
end

--设置当前回收绳子的速度
function XUiGoldenMinerBattle:SetCurShortenSpeed(speed)
    self.CurShortenSpeed = speed
end

--更新当前正在回收绳子时的速度
function XUiGoldenMinerBattle:UpdateCurShortenSpeed(speed)
    local baseSpeed = speed or self.ShortenSpeed or 0
    local totalWeight = self:GetCurTriggerObjTotalWeight()
    local denominator = totalWeight + SHORTEN_SPEED_PARAMETER
    denominator = XTool.IsNumberValid(denominator) and denominator or 1
    baseSpeed = baseSpeed * (1 - (totalWeight / denominator))
    self:SetCurShortenSpeed(math.max(SHORTEN_MIN_SPEED, baseSpeed))
end

--设置绳子伸长速度
function XUiGoldenMinerBattle:SetStretchSpeed(speed)
    self.StretchSpeed = speed
end

--设置角色移动速度
function XUiGoldenMinerBattle:SetHumenMoveSpeed(speed)
    self.HumenMoveSpeed = speed
end

--设置绳子摇摆速度
function XUiGoldenMinerBattle:SetRopeRockSpeed(speed)
    self.RopeRockSpeed = speed
end

--设置钩爪类型
function XUiGoldenMinerBattle:SetFalculaType(type)
    self.FalculaType = type
end

function XUiGoldenMinerBattle:GetFalculaType()
    return self.FalculaType
end

--是否显示瞄准线
function XUiGoldenMinerBattle:SetIsShowAim(isShow)
    self.IsShowAim = isShow
end

--获得抓取物分数上升倍率，默认1
function XUiGoldenMinerBattle:GetStoneUpScoreMultiple(goldenMinerStoneType)
    local multiple = self.StoneUpScoreDic[goldenMinerStoneType]
    return multiple and multiple / PERCENT or 1
end

--获得抓取物分数
function XUiGoldenMinerBattle:GetStoneScore(goldenMinerObject)
    local goldenMinerStoneType = goldenMinerObject:GetType()
    local score = 0

    --鼬鼠需要额外算上携带物的倍率
    if goldenMinerStoneType == XGoldenMinerConfigs.StoneType.Mouse then
        local carryStoneId = goldenMinerObject:GetCurCarryStoneId()
        if XTool.IsNumberValid(carryStoneId) then
            local stoneType = XGoldenMinerConfigs.GetStoneType(carryStoneId)
            score = score + goldenMinerObject:GetCarryStoneScore() * self:GetStoneUpScoreMultiple(stoneType)
        end
    end

    score = score + goldenMinerObject:GetScore() * self:GetStoneUpScoreMultiple(goldenMinerStoneType)

    return score
end
-----------Buff相关 end-----------------

-----------角色状态 begin---------------
--按下屏幕，角色左右移动
local _Screen = CS.UnityEngine.Screen
function XUiGoldenMinerBattle:OnPointerDown(eventData)
    if self:GetCurState() ~= RopeState.Rock then
        return
    end

    local eventPosX = eventData.position.x
    if eventPosX < _Screen.width / 2 then
        --向左移动
        self:SetHumenCurState(HumenState.MoveLeft)
    else
        --向右移动
        self:SetHumenCurState(HumenState.MoveRight)
    end
end

function XUiGoldenMinerBattle:OnPointerUp()
    self:SetHumenCurState(HumenState.Idle)
end

function XUiGoldenMinerBattle:HumenMoveLeft()
    local changePosX = self.Humen.transform.localPosition.x - self:GetDeltaTime() * self.HumenMoveSpeed
    if not self:CheckHumenMove(changePosX) then
        return
    end
    self.Humen.transform.localPosition = Vector3(changePosX, self.HumenPosY, 0)
end

function XUiGoldenMinerBattle:HumenMoveRight()
    local changePosX = self.Humen.transform.localPosition.x + self:GetDeltaTime() * self.HumenMoveSpeed
    if not self:CheckHumenMove(changePosX) then
        return
    end
    self.Humen.transform.localPosition = Vector3(changePosX, self.HumenPosY, 0)
end

function XUiGoldenMinerBattle:SetHumenCurState(state)
    self.HumenCurState = state
end

local _HumenCurPosX
function XUiGoldenMinerBattle:CheckHumenMove(changePosX)
    _HumenCurPosX = self.Humen.transform.localPosition.x
    --锚点在中间
    if MahtAbs(changePosX * 2) >= self.RoleMoveRange then
        self:SetHumenCurState(HumenState.Idle)
        return false
    end
    return true
end
-----------角色状态 end---------------

-----------绳子状态 begin---------------
local _RopeLength
local _Scale
function XUiGoldenMinerBattle:Rock()
    if self.RopeTrans.localRotation.z <= -0.5 then
        self.RopeRockDir = Vector3.forward
    elseif self.RopeTrans.localRotation.z >= 0.5 then
        self.RopeRockDir = Vector3.back
    end
    self.RopeTrans:Rotate(self.RopeRockDir * self.RopeRockSpeed * self:GetDeltaTime())
end

function XUiGoldenMinerBattle:Stretch()
    _RopeLength = self.RopeLength + self:GetDeltaTime() * self.StretchSpeed
    self:SetRopeLength(_RopeLength)
    self:SetRopeCordPosY(self.RopeMinLength - self.RopeRectTrans.sizeDelta.y)
    if _RopeLength >= self.RopeMaxLength then
        self:SetCurState(RopeState.Shorten)
    end
end

function XUiGoldenMinerBattle:Shorten()
    if self.RopeLength <= self.RopeMinLength then
        self:SetRopeLength(self.RopeMinLength)
        self:SetRopeCordPosY(0)
        self:CheckRoleGrapSuccess()
        self:UpdateCurScore()
        self:SetCurState(RopeState.Rock)
        return
    end

    _RopeLength = self.RopeLength - self:GetDeltaTime() * self.CurShortenSpeed
    self:SetRopeLength(_RopeLength)
    self:SetRopeCordPosY(self.RopeMinLength - self.RopeRectTrans.sizeDelta.y)
end

--设置绳子高度
function XUiGoldenMinerBattle:SetRopeHeight(height)
    self.RopeRectTrans.sizeDelta = Vector2(self.RopeRectTrans.sizeDelta.x, height)
end

--设置绳子节点下的Y轴
--ropeLengthLerp：当前绳子长度和原始长度的差值
local _localPosition
function XUiGoldenMinerBattle:SetRopeCordPosY(ropeLengthLerp)
    if self.RopeCordLeftTrans then
        _localPosition = self.RopeCordLeftTrans.localPosition
        self.RopeCordLeftTrans.localPosition = Vector3(_localPosition.x, self.RopeCordLeftOriginPosY + ropeLengthLerp, _localPosition.z)
    end
    if self.RopeCordRightTrans then
        _localPosition = self.RopeCordRightTrans.localPosition
        self.RopeCordRightTrans.localPosition = Vector3(_localPosition.x, self.RopeCordRightOriginPosY + ropeLengthLerp, _localPosition.z)
    end
    if self.RopeCordMagneticTrans then
        _localPosition = self.RopeCordMagneticTrans.localPosition
        self.RopeCordMagneticTrans.localPosition = Vector3(_localPosition.x, self.RopeCordMagneticOriginPosY + ropeLengthLerp, _localPosition.z)
    end
    if self.ShackleTrans then
        _localPosition = self.ShackleTrans.localPosition
        self.ShackleTrans.localPosition = Vector3(_localPosition.x, self.ShackleOriginPosY + ropeLengthLerp, _localPosition.z)
    end
    _localPosition = self.RopeCordTrans.localPosition
    self.RopeCordTrans.localPosition = Vector3(_localPosition.x, self.RopeCordOriginPosY + ropeLengthLerp, _localPosition.z)
end

function XUiGoldenMinerBattle:SetRopeLength(length)
    self.RopeLength = length
    self:SetRopeHeight(length)
end

--设置当前绳子的状态
--boomObj：在地图中的炸弹对象
function XUiGoldenMinerBattle:SetCurState(state, boomObj)
    local falculaType = self:GetFalculaType()

    --电磁钩爪不播放夹子动画，直接回收
    if state == RopeState.Stop and falculaType == XGoldenMinerConfigs.FalculaType.Magnetic then
        state = RopeState.Shorten
        if boomObj then
            self:TriggerBoom(boomObj)
        end
    end

    --播放和停止音效
    if state == RopeState.Stretch then
        XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetStretchSound(), XSoundManager.SoundType.Sound)
    else
        XSoundManager.Stop(XGoldenMinerConfigs.GetStretchSound())
    end
    if state == RopeState.Shorten then
        XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetShortenSound(), XSoundManager.SoundType.Sound)
    else
        XSoundManager.Stop(XGoldenMinerConfigs.GetShortenSound())
    end

    local isPlayRopeAnima = self.CurState ~= state
    self.CurState = state
    if isPlayRopeAnima then
        self:PlayRopeAnima(state, boomObj)
    end
    if state == RopeState.Stop then
        --普通钩爪停止移动播放动画时，关闭触发器检测
        if falculaType == XGoldenMinerConfigs.FalculaType.Normal then
            self:SetRopeCordColliderActive(false)
        end
        return
    end

    local notActiveBoomTimes = self:GetNotActiveBoomTimes()
    if state == RopeState.Shorten and notActiveBoomTimes > 0 then
        self:SetNotActiveBoomTimes(notActiveBoomTimes - 1)
    end

    self:SetIsActiveBoom(state == RopeState.Stretch and notActiveBoomTimes <= 0)

    self:UpdateCurShortenSpeed()
    self:SetAimActive(state == RopeState.Rock and self.IsShowAim)
    self:SetRopeCordColliderActive(state == RopeState.Stretch)

    if state == RopeState.Shorten then
        self:CheckRoleGrapingFace()
    end

    if state == RopeState.Rock then
        self:CheckGameOver()
    end
end

--播放夹子动画
function XUiGoldenMinerBattle:PlayRopeAnima(state, boomObj)
    --未抓到物品碰到边界回到摇摆状态时，不播放夹子打开的动画
    if state == RopeState.Stretch then
        self:SetIsPlayRopeOpenAnima(false)
    elseif state == RopeState.Rock and not self:GetIsPlayRopeOpenAnima() then
        self:SetIsPlayRopeOpenAnima(true)
        return
    end

    local animaName
    local falculaType = self:GetFalculaType()
    if falculaType == XGoldenMinerConfigs.FalculaType.Normal then
        animaName = (state == RopeState.Rock and "NormalRopeOpen") or (state == RopeState.Stop and "NormalRopeClose")
    elseif falculaType == XGoldenMinerConfigs.FalculaType.Big then
        animaName = (state == RopeState.Rock and "BigRopeOpen") or (state == RopeState.Stop and "BigRopeClose")
    end

    if state == RopeState.Stop then
        self:SetIsPlayRopeOpenAnima(true)
    end

    if animaName then
        self:PlayAnimation(animaName, function()
            if state == RopeState.Stop then
                if not boomObj then
                    self:SetObjToTriggerParent()
                else
                    self:TriggerBoom(boomObj)
                end
                self:SetCurState(RopeState.Shorten)
            end
        end)
    end
end

function XUiGoldenMinerBattle:SetIsPlayRopeOpenAnima(isPlay)
    self.IsPlayRopeAnima = isPlay
end

function XUiGoldenMinerBattle:GetIsPlayRopeOpenAnima()
    return self.IsPlayRopeAnima
end

function XUiGoldenMinerBattle:GetCurState()
    return self.CurState
end

--设置不激活炸药箱的次数
function XUiGoldenMinerBattle:SetNotActiveBoomTimes(times)
    self.NotActiveBoomTimes = times
end

function XUiGoldenMinerBattle:GetNotActiveBoomTimes()
    return self.NotActiveBoomTimes
end

function XUiGoldenMinerBattle:SetIsActiveBoom(isActive)
    for _, boomObj in ipairs(self.BoomObjList) do
        boomObj:SetGoInputHandlerActive(isActive)
    end
end

function XUiGoldenMinerBattle:SetAimActive(isActive)
    self.Aim.gameObject:SetActiveEx(isActive)
end
-----------绳子状态 end---------------

-----------钩子触发器相关 begin------------
function XUiGoldenMinerBattle:SetRopeCordColliderActive(isActive)
    if self:GetFalculaType() == XGoldenMinerConfigs.FalculaType.Big then
        self.BigRopeCordLeftCollider.enabled = isActive
        self.BigRopeCordRightCollider.enabled = isActive
        return
    end

    if XTool.UObjIsNil(self.RopeCordCollider) then
        XLog.Error("黄金矿工钩子上的触发器不存在")
        return
    end
    self.RopeCordCollider.enabled = isActive
end

function XUiGoldenMinerBattle:TrigerCallback(goldenMinerObject)
    local stoneType = goldenMinerObject:GetType()
    local falculaType = self:GetFalculaType()

    if stoneType ~= XGoldenMinerConfigs.StoneType.Boom then
        self.CurTriggerObjDic[goldenMinerObject:GetIndex()] = goldenMinerObject
    end

    if stoneType == XGoldenMinerConfigs.StoneType.Boom then
        self:SetCurState(RopeState.Stop, goldenMinerObject)
        return
    elseif falculaType == XGoldenMinerConfigs.FalculaType.Magnetic then
        goldenMinerObject:SetObjToTriggerParent(self.TriggerObjs)
        return
    end

    self:SetCurState(RopeState.Stop)
end

function XUiGoldenMinerBattle:OnEdgeTriggerEnter(collider)
    self:SetCurState(RopeState.Shorten)
end

function XUiGoldenMinerBattle:SetObjToTriggerParent()
    for _, v in pairs(self.CurTriggerObjDic) do
        v:SetObjToTriggerParent(self.TriggerObjs)
    end
end

--碰到炸弹
function XUiGoldenMinerBattle:TriggerBoom(boomObj)
    if (boomObj) and not XTool.UObjIsNil(boomObj.GameObject) then
        local effect = XGoldenMinerConfigs.GetStoneCatchEffect(boomObj:GetId())
        local boomObjPos = self.PanelPlay.transform:InverseTransformPoint(boomObj.Transform.position)
        self:LoadEffect(effect, self.PanelPlay, boomObjPos)
        boomObj:SetObjToTriggerParent()
    end
    self:RemoveCurTriggerObjDic()
    self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleGrapBoom)
end
-----------钩子触发器相关 end--------------

-----------表情相关 begin------------
--检查表情，返回是否可切换表情
function XUiGoldenMinerBattle:CheckFace()
    if XTool.IsNumberValid(self.MouseRecoverMoveTime) and self.MouseRecoverMoveTime <= self.LastTime then
        self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleUseMouseStop)
        return false
    end
    self.MouseRecoverMoveTime = 0

    if XTool.IsNumberValid(self.RoleGrapSuccessTime) and self.RoleGrapSuccessTime <= self.LastTime then
        return false
    end
    self.RoleGrapSuccessTime = 0
    
    return true
end

--检查角色成功拉回表情
function XUiGoldenMinerBattle:CheckRoleGrapSuccess()
    local score = self:GetCurTriggerObjTotalScore()
    self:SetRoleFaceByGroup(XGoldenMinerConfigs.FaceGroup.RoleGrapSuccess, score)
    self.RoleGrapSuccessTime = self.LastTime - ROLE_GRAP_SUCCESS_TIME / MILLISECOND
end

--检查角色拉回的表情
function XUiGoldenMinerBattle:CheckRoleGrapingFace()
    --没抓到任何东西
    if XTool.IsTableEmpty(self.CurTriggerObjDic) then
        self:SetRoleFace(XGoldenMinerConfigs.FaceId.RoleCantGrap)
        return
    end

    local weight = self:GetCurTriggerObjTotalWeight()
    self:SetRoleFaceByGroup(XGoldenMinerConfigs.FaceGroup.RoleGraping, weight)
end

--策划需求：不显示默认表情了
function XUiGoldenMinerBattle:SetRoleDefaultFace()
    if not self:CheckFace() then
        return
    end
    if self.PreFaceUrlPath == self.DefaultFaceImgPath then
        return
    end

    self:PlayAnimation("PanelEmoticonDisable")
    self.PreFaceUrlPath = self.DefaultFaceImgPath
end

function XUiGoldenMinerBattle:SetRoleFace(faceId)
    if self.CurFaceId == faceId then
        return
    end

    local img = XGoldenMinerConfigs.GetFaceImage(faceId)
    if self.PreFaceUrlPath == img then
        return
    end

    local isPlayDisable = self.DefaultFaceImgPath ~= self.PreFaceUrlPath

    self.PreFaceUrlPath = img
    if isPlayDisable then
        self:PlayAnimation("PanelEmoticonDisable", function()
            if not XTool.UObjIsNil(self.RImgHate) then
                self.RImgHate:SetRawImage(img)
            end
            self:PlayAnimation("PanelEmoticonEnable")
        end)
    else
        if not XTool.UObjIsNil(self.RImgHate) then
            self.RImgHate:SetRawImage(img)
        end
        self:PlayAnimation("PanelEmoticonEnable")
    end
    self.CurFaceId = faceId

    self:CheckFace()
end

function XUiGoldenMinerBattle:SetRoleFaceByGroup(groupId, value)
    local faceId = XGoldenMinerConfigs.GetFaceIdByGroup(groupId, value)
    self:SetRoleFace(faceId)
end
-----------表情相关 end--------------

--获得拉取中的物品总积分
function XUiGoldenMinerBattle:GetCurTriggerObjTotalScore()
    local score = 0
    for _, obj in pairs(self.CurTriggerObjDic) do
        score = score + self:GetStoneScore(obj)
    end
    return score
end

--获得拉取中的物品总重量
function XUiGoldenMinerBattle:GetCurTriggerObjTotalWeight()
    local weight = 0
    for _, obj in pairs(self.CurTriggerObjDic) do
        weight = weight + obj:GetWeight()
    end
    return weight
end

function XUiGoldenMinerBattle:UpdateCurScore()
    local score
    for _, goldenMinerObject in pairs(self.CurTriggerObjDic) do
        score = self:GetStoneScore(goldenMinerObject)
        self:AddCurMapScore(score)
        self:CheckRedEnvelopeItem(goldenMinerObject)
        TableInsert(self.CurTriggerObjSettleList, goldenMinerObject)
    end

    self:RemoveCurTriggerObjDic()

    self:UpdateTextCurScore()
end

function XUiGoldenMinerBattle:UpdateTextCurScore()
    local score = self.CurMapScore
    if not self.OriginScore then
        self.OriginScore = score
        self.CurScore.text = XUiHelper.GetText("GoldenMinerPlayCurScore", self.CurMapScore)
    elseif self.OriginScore ~= score then
        self:PlayCurScoreChangeAnima(score - self.OriginScore, self.OriginScore)
        self.OriginScore = score
    end
end

--检查红包箱是否能获得道具
function XUiGoldenMinerBattle:CheckRedEnvelopeItem(goldenMinerObject)
    local dataDb = self.DataDb
    local itemColumnIndex = dataDb:GetEmptyItemIndex()
    if not goldenMinerObject.GetItemId or not itemColumnIndex then
        return
    end

    local itemId = goldenMinerObject:GetItemId()
    if not XTool.IsNumberValid(itemId) then
        return
    end

    dataDb:UpdateItemColumn(itemId, itemColumnIndex)
    self.ItemPanel:UpdateItemColumns()
    self:UpdateItemChangeInfo(itemColumnIndex, XGoldenMinerConfigs.ItemChangeType.OnGet)
end

function XUiGoldenMinerBattle:AddCurMapScore(score)
    if XTool.IsNumberValid(score) then
        XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetAddScoreSound(), XSoundManager.SoundType.Sound)
    end
    self.CurMapScore = math.floor(self.CurMapScore + score)
end

function XUiGoldenMinerBattle:RemoveCurTriggerObjDic(isBoom)
    self:DestroyAllChildObj(isBoom)
    self:UpdateCurShortenSpeed()
end

function XUiGoldenMinerBattle:DestroyAllChildObj(isBoom)
    for _, v in pairs(self.CurTriggerObjDic) do
        v:DestroySelf(isBoom)
    end
    self.CurTriggerObjDic = {}
end

--没物品可以抓时直接游戏结束
function XUiGoldenMinerBattle:CheckGameOver()
    local transform = self.PanelStone.transform
    if not XTool.IsNumberValid(transform.childCount) then
        self:GameOver()
    end
end

function XUiGoldenMinerBattle:GameOver()
    self:StopTimer()
    self:UpdateSettlementInfo()

    local curMapScore = self.CurMapScore
    local mapId = self.MapId
    local curStageId = self.CurStageId
    self.IsWin = curMapScore >= self.TargetScoreData

    local closeCb = handler(self, self.CheckGameState)
    local isCloseFunc = handler(self, self.GetIsCloseBattle)
    local data = {
        CurStageId = curStageId,
        CurMapId = mapId,
        CurStageIndex = self.CurStageIndex,
        BeforeScore = self.BeforeScore,
        CurMapScore = curMapScore,
        GoldenMinerObjectList = self.CurTriggerObjSettleList,
        TargetScore = self.TargetScoreData,
    }
    XLuaUiManager.Open("UiGoldenMinerReport", data, closeCb, isCloseFunc)
    XDataCenter.GoldenMinerManager.RequestGoldenMinerFinishStage(curStageId, self.SettlementInfo, curMapScore, function(isFinishSuccess)
        self.IsCloseBattle = true
        self.IsFinishSuccess = isFinishSuccess
    end, self.IsWin)
end

function XUiGoldenMinerBattle:GetIsCloseBattle()
    return self.IsCloseBattle
end

--刷新发给后端的关卡结算数据
function XUiGoldenMinerBattle:UpdateSettlementInfo()
    local mapId = self.MapId
    local mapTime = XGoldenMinerConfigs.GetMapTime(mapId)
    self.SettlementInfo:SetScores(self.CurMapScore - self.BeforeScore)
    self.SettlementInfo:SetCostTime(MathFloor(mapTime - self.LastTime))
    self.SettlementInfo:UpdateGrabDataInfos(self.CurTriggerObjSettleList)
end

function XUiGoldenMinerBattle:ResourceManagerLoad(path)
    local resource = self.ResourcePool[path]
    if resource then
        return resource
    end
    resource = CSXResourceManagerLoad(path)
    if resource == nil or not resource.Asset then
        XLog.Error(string.format("XUiGoldenMinerBattle:ResourceManagerLoad加载资源，路径：%s", path))
        return
    end

    self.ResourcePool[path] = resource
    return resource
end

--加载特效
function XUiGoldenMinerBattle:LoadEffect(path, parent, localPosition)
    if XTool.UObjIsNil(parent) then
        return
    end

    local model = self.EffectPool[path]
    if XTool.UObjIsNil(model) then
        local resource = self:ResourceManagerLoad(path)
        model = XUiHelper.Instantiate(resource.Asset, parent)
        self.EffectPool[path] = model
    end

    model.transform.localPosition = localPosition or Vector3.zero

    model.gameObject:SetActiveEx(false)
    model.gameObject:SetActiveEx(true)
    return model
end

function XUiGoldenMinerBattle:CheckGameState()
    local nextStageId = self.DataDb:GetCurStageId()
    if (not self.IsWin or not nextStageId) or (not self.IsFinishSuccess and self.CurStageIndex == 1) then
        XLuaUiManager.PopThenOpen("UiGoldenMinerMain")
        return
    end
    XLuaUiManager.PopThenOpen("UiGoldenMinerShop")
end

function XUiGoldenMinerBattle:SetHumenEffectActive(isActive)
    if self.HumenEffect then
        self.HumenEffect.gameObject:SetActiveEx(isActive)
    end
end

function XUiGoldenMinerBattle:GetBoomObj(index)
    for _, boomObj in ipairs(self.BoomObjList) do
        if boomObj:GetIndex() == index then
            return boomObj
        end
    end
end

local _deltaTime
function XUiGoldenMinerBattle:GetDeltaTime()
    _deltaTime = CSUnityEngineTime.deltaTime
    --防止卡顿跳帧
    if _deltaTime > 0.05 then
        _deltaTime = 0.05
    end
    return _deltaTime
end

--检查绳子的音效播放
function XUiGoldenMinerBattle:CheckRopeSoundPlay()
    local curState = self:GetCurState()
    if curState == RopeState.Stretch then
        XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetStretchSound(), XSoundManager.SoundType.Sound)
    elseif curState == RopeState.Shorten then
        XSoundManager.PlaySoundByType(XGoldenMinerConfigs.GetShortenSound(), XSoundManager.SoundType.Sound)
    end
end

function XUiGoldenMinerBattle:StopRopeSoundPlay()
    XSoundManager.Stop(XGoldenMinerConfigs.GetShortenSound())
    XSoundManager.Stop(XGoldenMinerConfigs.GetStretchSound())
end

---------------抓取成功播放动画 begin----------------
function XUiGoldenMinerBattle:PlayCurScoreChangeAnima(changeScore, originScore)
    self:ShowCurScoreChange("+" .. changeScore)
    self:StopCurScoreChangeAnima()

    local scores = self.DataDb:GetStageScores()
    self.CurScoreChangeAnima = XUiHelper.Tween(1, function(f)
        self:ShowCurScoreChange("+" .. changeScore)
        self.CurScore.text = XUiHelper.GetText("GoldenMinerPlayCurScore", math.floor(originScore + changeScore * f))
    end, function()
        self.CurScore.text = XUiHelper.GetText("GoldenMinerPlayCurScore", self.CurMapScore)
    end)

    if self.PanelCurScoreChange then
        self.PanelCurScoreChange.gameObject:SetActiveEx(true)
        self:PlayAnimation("BubbleEnable")
    end
end

function XUiGoldenMinerBattle:StopCurScoreChangeAnima()
    if self.CurScoreChangeAnima then
        XScheduleManager.UnSchedule(self.CurScoreChangeAnima)
        self.CurScoreChangeAnima = nil
    end
end

function XUiGoldenMinerBattle:ShowCurScoreChange(score)
    if self.TxtCurScoreChange then
        self.TxtCurScoreChange.text = score
    end
end

function XUiGoldenMinerBattle:HideCurScoreChange()
    if self.PanelCurScoreChange then
        self.PanelCurScoreChange.gameObject:SetActiveEx(false)
    end
end
---------------抓取成功播放动画 end------------------