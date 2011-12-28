--
-- $Date $Revision$
--

NQS = LibStub("AceAddon-3.0"):NewAddon(
    "NADTQuestShare",
    "AceConsole-3.0",
	"AceComm-3.0",
	"AceEvent-3.0"
)

local playerName = UnitName("player")
local myquests = {}
local myoldquests = nil
local slavequests = {}

function NQS:OnEnable()

	-- common
	self:RegisterEvent("QUEST_LOG_UPDATE")

	-- master
	if NQS_DB.mode == "master" then
		self:RegisterEvent("QUEST_ACCEPTED", "QUEST_ACCEPTED_MASTER")
		self:Print("NADTQuestShare initialized - master")
	end
	
	-- slave
	if NQS_DB.mode == "slave" then
		self:RegisterEvent("QUEST_ACCEPTED", "QUEST_ACCEPTED_SLAVE")
		self:RegisterEvent("QUEST_ACCEPT_CONFIRM")
		self:Print("NADTQuestShare initialized - slave")
	end
	
	-- register for addon messages
	self:RegisterComm("nqs")

end

-- handle incoming addon messages
function NQS:OnCommReceived(prefix, message, distribution, sender)

	-- actions
	-- ACCEPTED qlink = sender accepted a quest
	-- TURNEDIN qlink = sender turned in a quest
	-- DOYOUHAVE qid = sender wants to know if we have a specifid quest in our log
	-- DONOTHAVE qid = sender does not have a specific quest in their log

	if prefix ~= "nqs" or distribution ~= "PARTY" or sender == playerName or not NTL:IsUnitTrusted(sender) then return end
	
	local verb, rest = message:match( "^(%S+) (.+)$" )
	
	if verb == "ACCEPTED" then
		local qlink = rest
		local qid = self:GetQuestIdForLink(qlink)
		self:Print(sender, "accepted", qlink)
		if NQS_DB.mode == "master" then
			slavequests[qid] = 1
		end
	elseif verb == "TURNEDIN" then
		local qlink = rest
		local qid = self:GetQuestIdForLink(qlink)
		self:Print(sender, "turned in", qlink)
		if NQS_DB.mode == "master" then
			slavequests[qid] = nil
		end
	elseif verb == "DOYOUHAVE" then
		local qid = tonumber(rest)
		if not myquests.qid then
			SendAddonMessage( "nqs", "DONOTHAVE " .. qid, "PARTY" )
		end
	elseif verb == "DONOTHAVE" then
		local qid = tonumber(rest)
		self:ShareQuestById(qid)
	end
end

-- accepts quests shared to us by trusted people
function NQS:QUEST_ACCEPT_CONFIRM(name, qname)
	if not NTL:UnitIsTrusted(name) then return end
	self:Print("Accepting quest", qname, "started by", name)
	ConfirmAcceptQuest()
	StaticPopup_Hide("QUEST_ACCEPT")
end

-- we have accepted a quest (slave)
function NQS:QUEST_ACCEPTED_MASTER(event, index)
	local qlink = GetQuestLink( index )
	local qid = self:GetQuestIdForLink( qlink )
	SendAddonMessage( "nqs", "ACCEPTED " .. qlink, "PARTY" )
	SendAddonMessage( "nqs", "DOYOUHAVE " .. qid, "PARTY" )
end

-- we have accepted a quest (slave)
function NQS:QUEST_ACCEPTED_SLAVE(event, index)
	SendAddonMessage( "nqs", "ACCEPTED " .. GetQuestLink(index), "PARTY" )
end

-- our quest log has changed
function NQS:QUEST_LOG_UPDATE(event)
	
	self:Print("quest log updated")
	
	if( nil == myoldquests ) then
		self:Print("doing first time quest log scanning")
		myoldquests = {}
		self:PopulateMyQuests()
		return
	else
		-- keep a copy of the quest log as it existed before the update
		self:Print("size of myquests is", #myquests)
		self:Print("size of myoldquests is", #myquests)
		myoldquests = myquests
		self:PopulateMyQuests()
		self:Print("after swap, size of myquests is", #myquests)
		self:Print("after swap size of myoldquests is", #myquests)
	end
	
	-- iterate over old quests, reporting as turned in any that aren't in current
	for qid, qlink in pairs(myoldquests) do
		self:Print("checking if qid", qid, "is in current")
		if not myquests.qid then
			self:Print("qid", qid, "IS NOT in current")
			SendAddonMessage( "nqs", "TURNEDIN " .. link, "PARTY" )
		else
			self:Print("qid", qid, "IS in current")
		end
	end
	
	-- slave can exit out here
	if NQS_DB.mode == "slave" then return end
	
	-- iterate over current quests, checking for ones that aren't in the old list
	for qid, qlink in pairs(myquests) do
		if not myoldquests[qid] then
			SendAddonMessage( "nqs", "DOYOUHAVE " .. qid, "PARTY" )
		end
	end
	
end

function NQS:PopulateMyQuests()
	self:Print("before populate, size of myquests is", #myquests)
	-- build up a map of the quest in our log, qid => qlink
	wipe(myquests)
	for i = 1, GetNumQuestLogEntries() do
		local link = GetQuestLink(i)
		if link then
			local qid = self:GetQuestIdForLink(link)
			myquests.qid = link
		end
	end
	self:Print("after populate, size of myquests is", #myquests)
end

-- get the quest id for a quest link
function NQS:GetQuestIdForLink(qlink)
	local qid = qlink:match("|Hquest:(%d+):")
	return tonumber(qid)
end

-- get the quest id for a quest index
function NQS:GetQuestIdForIndex(index)
	return select(9, GetQuestLogTitle(index))
end

-- share a quest by id
function NQS:ShareQuestById(qid)

	-- only share in trusted parties
	if NTL:IsGroupTrusted() then
	
		-- find the quest
		local title, thisqid
		for i = 1, GetNumQuestLogEntries() do
			local thisqid = select(9, GetQuestLogTitle(i))
			if qid == thisqid then
				local qlink = GetQuestLink(i)
				SelectQuestLogEntry( i )
				if GetQuestLogPushable() then
					QuestLogPushQuest()
				else
					self:Print(qlink, "is not shareable")
				end
			end
		end
	end
	
end

--
-- EOF
