local XUiGridEquip = require("XUi/XUiEquipAwarenessReplace/XUiGridEquip")
local XUiGridSuitDetail = require("XUi/XUiEquipAwarenessReplace/XUiGridSuitDetail")
local XUiGridBagPartner = require("XUi/XUiPartner/PartnerCommon/XUiGridBagPartner")
local XUiPanelBagItem = XClass(nil, "XUiPanelBagItem")

function XUiPanelBagItem:Ctor(ui)
    self.GameObject = ui.gameObject
    self.Transform = ui.transform
    XTool.InitUiObject(self)
end

function XUiPanelBagItem:Init(rootUi, page, isfirstanimation)
    self.GameObject:SetActive(true)
    self.Parent = rootUi
    self.Page = page
    self.IsFirstAnimation = isfirstanimation
    local clickCb = function(data, grid)
        self.Parent:OnGridClick(data, grid)
    end

    self.EquipGrid = XUiGridEquip.New(self.GridEquip, clickCb, rootUi)
    self.SuitGrid = XUiGridSuitDetail.New(self.GridSuitSimple, rootUi, clickCb)
    self.BagItemGrid = XUiBagItem.New(rootUi, self.GridBagItem, nil, clickCb)
    self.BagPartnerGrid = XUiGridBagPartner.New(self.GridPartner, clickCb)
end

function XUiPanelBagItem:SetupCommon(data, pageType, operation, gridSize)
    self.BagItemGrid:Refresh(data)
    self.BagItemGrid.GameObject:SetActive(true)
    self.GridBagItemRect.sizeDelta = gridSize
    self.EquipGrid.GameObject:SetActive(false)
    self.SuitGrid.GameObject:SetActive(false)
    self.BagPartnerGrid.GameObject:SetActive(false)
end

function XUiPanelBagItem:SetupEquip(equipId, gridSize)
    self.EquipGrid:Refresh(equipId)
    self.EquipGrid.GameObject:SetActive(true)
    self.GridEquipRect.sizeDelta = gridSize
    self.SuitGrid.GameObject:SetActive(false)
    self.BagItemGrid.GameObject:SetActive(false)
    self.BagPartnerGrid.GameObject:SetActive(false)
end

function XUiPanelBagItem:SetupSuit(suitId, defaultSuitIds, gridSize)
    self.SuitGrid:Refresh(suitId, defaultSuitIds, true)
    self.SuitGrid.GameObject:SetActive(true)
    self.GridSuitSimpleRect.sizeDelta = gridSize
    self.EquipGrid.GameObject:SetActive(false)
    self.BagItemGrid.GameObject:SetActive(false)
    self.BagPartnerGrid.GameObject:SetActive(false)
end

function XUiPanelBagItem:SetupPartner(partner, gridSize, isInPrefab)
    self.BagPartnerGrid:UpdateGrid(partner, isInPrefab)
    self.BagPartnerGrid.GameObject:SetActive(true)
    self.BagPartnerGrid.sizeDelta = gridSize
    self.EquipGrid.GameObject:SetActive(false)
    self.BagItemGrid.GameObject:SetActive(false)
    self.SuitGrid.GameObject:SetActive(false)
end

function XUiPanelBagItem:SetSelectedEquip(bSelect)
    self.EquipGrid:SetSelected(bSelect)
end

function XUiPanelBagItem:SetSelectedCommon(bSelect)
    self.BagItemGrid:SetSelectState(bSelect)
end

function XUiPanelBagItem:SetSelectedPartner(bSelect)
    self.BagPartnerGrid:SetSelected(bSelect)
end

function XUiPanelBagItem:PlayAnimation()
    if not self.IsFirstAnimation then
        return
    end

    self.IsFirstAnimation = false
    if self.Page == XItemConfigs.PageType.Equip or self.Page == XItemConfigs.PageType.Awareness then
        self.GridEquipTimeline:PlayTimelineAnimation()
    elseif self.Page == XItemConfigs.PageType.SuitCover then
        self.GridSuitSimpleTimeline:PlayTimelineAnimation()
    elseif self.Page == XItemConfigs.PageType.Partner then
        self.GridPartnerTimeline:PlayTimelineAnimation()
    else
        self.GridBagItemTimeline:PlayTimelineAnimation()
    end
end

return XUiPanelBagItem